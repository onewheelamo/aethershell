"""Le launcher, côté données : une requête préfixée, une liste de résultats.

`spotlight.qml` garde ce qu'il fait déjà bien (index des applications, alias,
historique, et le mode `>`), et lui délègue tout ce qui commence par un préfixe :
calcul, fichiers, contenu, presse-papiers, émoji, unités, devises, processus,
signets, aide.

    python3 launcher_service.py --query "=2+2"
    python3 launcher_service.py --query "/facture" --limit 8

Sortie : {"ok": true, "prefix": "/", "kind": "fichiers", "results": [...]}

Un résultat porte : kind, name, detail, icon, tag, et **une** action —
`exec` (commande à lancer) ou `action` (copier, ouvrir, révéler, tuer). Le QML
sait exécuter les deux ; c'est ce champ qui manquait pour que le launcher puisse
faire autre chose que lancer un programme.

Tout est borné : nombre de résultats, profondeur, durée. Une requête ne doit
jamais faire geler la pilule.
"""
from __future__ import annotations

import ast
import heapq
import json
import math
import os
import re
import shlex
import shutil
import subprocess
import sqlite3
import sys
import time
import urllib.request
from pathlib import Path

HOME = Path.home()
CACHE = HOME / ".cache" / "quickshell"
LIMITE_DEFAUT = 8

# ── la table des préfixes : source unique du dispatch ET de l'aide ────────────
# Un symbole, un identifiant, un libellé, un exemple, une phrase. L'aide du
# launcher est générée d'ici : elle ne peut pas mentir sur ce qui existe.
PREFIXES = [
    (">", "commande", "Commande shell", "> nmcli device status",
     "Le reste de la requête part tel quel dans un shell."),
    ("=", "calc", "Calcul", "= 15% de 80",
     "Arithmétique, pourcentages, parenthèses. Entrée copie le résultat."),
    ("/", "fichiers", "Fichiers", "/ rapport",
     "Cherche un nom de fichier sous ~ (respecte les .gitignore)."),
    (":", "contenu", "Dans les fichiers", ": TODO",
     "Cherche le texte à l'intérieur des fichiers sous ~."),
    ('"', "presse", "Presse-papiers", '" http',
     "Historique cliphist. Entrée copie l'entrée."),
    (";", "emoji", "Émoji", "; coeur",
     "Cherche un émoji par nom ou mot-clé. Entrée le copie."),
    ("~", "unites", "Unités", "~ 12 km en mi",
     "Longueurs, masses, températures, volumes, durées, données."),
    ("$", "devises", "Devises", "$ 100 usd en eur",
     "Taux du jour (BCE), mis en cache 24 h."),
    ("%", "processus", "Processus", "% firefox",
     "Triés par CPU. Entrée envoie SIGTERM."),
    ("*", "signets", "Signets", "* doc python",
     "Signets de Firefox (profil le plus récent)."),
    ("?", "aide", "Aide", "?",
     "Cette liste, directement dans le launcher."),
]


# ── utilitaires ──────────────────────────────────────────────────────────────
def resultat(kind, name, detail="", icon="", tag="", exec_=None, action=None,
             arg=None):
    r = {"kind": kind, "name": name, "detail": detail, "icon": icon, "tag": tag}
    if exec_ is not None:
        r["exec"] = exec_
    if action is not None:
        r["action"] = action
        r["arg"] = arg if arg is not None else ""
    return r


# Dernier appel qui a dépassé son délai. Un `borne()` expiré rend "" — la même
# chose qu'une recherche sans résultat, d'où ce drapeau pour ne pas confondre les
# deux et annoncer « aucun résultat » sur une recherche interrompue.
INTERROMPU = {"valeur": False}


def borne_etat(cmd, timeout=2.5, **kw):
    """Comme `borne`, mais dit aussi si le délai a été dépassé."""
    INTERROMPU["valeur"] = False
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           errors="replace", **kw)
        return p.stdout
    except subprocess.TimeoutExpired:
        INTERROMPU["valeur"] = True
        return ""
    except (FileNotFoundError, OSError):
        return ""


def borne(cmd, timeout=2.5, **kw):
    """Lance une commande, rend sa sortie ou "" — jamais d'exception, jamais de blocage."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           errors="replace", **kw)
        return p.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return ""


def nombre_fr(x):
    """1 234,56 — la barre et le launcher parlent français."""
    if isinstance(x, int) or (isinstance(x, float) and x.is_integer()):
        entier = f"{int(x):,}".replace(",", "\u202f")
        return entier
    texte = f"{x:,.6f}".rstrip("0").rstrip(".").replace(",", "\u202f")
    return texte.replace(".", ",")


def score(q, texte):
    """Petit score de sous-séquence : 0 = pas de correspondance.

    Les correspondances contiguës et celles en début de mot comptent double, ce
    qui met « facture.pdf » devant « vieille-facture-archive.pdf » sur « fct ».
    """
    q = q.lower()
    t = texte.lower()
    if q in t:
        return 100 - t.index(q) - len(t) / 100.0
    j = 0
    points = 0
    dernier = -2
    for i, c in enumerate(t):
        if j < len(q) and c == q[j]:
            points += 1
            if i == dernier + 1:
                points += 1
            if i == 0 or t[i - 1] in " -_/.":
                points += 2
            dernier = i
            j += 1
    return points if j == len(q) else 0


# ── calcul ───────────────────────────────────────────────────────────────────
AUTORISE = (ast.Expression, ast.BinOp, ast.UnaryOp, ast.Constant, ast.Add,
            ast.Sub, ast.Mult, ast.Div, ast.FloorDiv, ast.Mod, ast.Pow,
            ast.UAdd, ast.USub, ast.USub)


def _evaluer(noeud):
    if isinstance(noeud, ast.Expression):
        return _evaluer(noeud.body)
    if isinstance(noeud, ast.Constant):
        if isinstance(noeud.value, (int, float)) and not isinstance(noeud.value, bool):
            return noeud.value
        raise ValueError("constante")
    if isinstance(noeud, ast.UnaryOp):
        v = _evaluer(noeud.operand)
        return -v if isinstance(noeud.op, ast.USub) else +v
    if isinstance(noeud, ast.BinOp):
        g, d = _evaluer(noeud.left), _evaluer(noeud.right)
        if isinstance(noeud.op, ast.Add):
            return g + d
        if isinstance(noeud.op, ast.Sub):
            return g - d
        if isinstance(noeud.op, ast.Mult):
            return g * d
        if isinstance(noeud.op, ast.Div):
            return g / d
        if isinstance(noeud.op, ast.FloorDiv):
            return g // d
        if isinstance(noeud.op, ast.Mod):
            return g % d
        if isinstance(noeud.op, ast.Pow):
            if abs(d) > 256:
                raise ValueError("exposant")
            return g ** d
    raise ValueError("expression")


def calcul(texte):
    brut = texte.strip().lstrip("=").strip()
    if brut == "":
        return []
    # « 15% de 80 », « 20 % de 250 » — la tournure qu'on tape naturellement.
    m = re.fullmatch(r"([\d.,\s+\-*/()]+?)\s*%\s*(?:de|of)\s*([\d.,\s+\-*/()]+)", brut)
    if m:
        brut = f"({m.group(1)})*({m.group(2)})/100"
    expr = (brut.replace(",", ".").replace("×", "*").replace("÷", "/")
                .replace("^", "**").replace("x", "*").replace(" ", ""))
    if not re.fullmatch(r"[0-9.+\-*/%()]*", expr):
        return []
    try:
        valeur = _evaluer(ast.parse(expr, mode="eval"))
    except (SyntaxError, ValueError, ZeroDivisionError, TypeError, OverflowError):
        return []
    if isinstance(valeur, float) and (math.isnan(valeur) or math.isinf(valeur)):
        return []
    texte_valeur = nombre_fr(valeur)
    return [resultat("calc", texte_valeur, brut.replace("*", " × ").replace("/", " ÷ "),
                     "", "calcul", action="copy", arg=texte_valeur)]


# ── unités ───────────────────────────────────────────────────────────────────
# Facteur vers l'unité de base de chaque famille ; les températures ont leur
# propre conversion (les échelles ne sont pas proportionnelles).
UNITES = {
    "mm": ("long", 0.001), "cm": ("long", 0.01), "m": ("long", 1.0),
    "km": ("long", 1000.0), "in": ("long", 0.0254), "ft": ("long", 0.3048),
    "yd": ("long", 0.9144), "mi": ("long", 1609.344), "nm": ("long", 1852.0),
    "mg": ("masse", 1e-6), "g": ("masse", 0.001), "kg": ("masse", 1.0),
    "t": ("masse", 1000.0), "oz": ("masse", 0.0283495), "lb": ("masse", 0.453592),
    "ml": ("vol", 0.001), "cl": ("vol", 0.01), "l": ("vol", 1.0),
    "gal": ("vol", 3.785412), "pinte": ("vol", 0.473176),
    "s": ("temps", 1.0), "min": ("temps", 60.0), "h": ("temps", 3600.0),
    "jour": ("temps", 86400.0), "semaine": ("temps", 604800.0),
    "ko": ("donnees", 1e3), "mo": ("donnees", 1e6), "go": ("donnees", 1e9),
    "to": ("donnees", 1e12), "kio": ("donnees", 1024.0), "mio": ("donnees", 1048576.0),
    "gio": ("donnees", 1073741824.0),
}
ALIAS_UNITES = {"metre": "m", "metres": "m", "mètre": "m", "mètres": "m",
                "kilometre": "km", "kilomètres": "km", "kilometres": "km",
                "mile": "mi", "miles": "mi", "pied": "ft", "pieds": "ft",
                "pouce": "in", "pouces": "in", "gramme": "g", "grammes": "g",
                "kilo": "kg", "kilos": "kg", "livre": "lb", "livres": "lb",
                "litre": "l", "litres": "l", "heure": "h", "heures": "h",
                "minutes": "min", "secondes": "s", "jours": "jour", "gigaoctet": "go",
                "gigaoctets": "go", "megaoctet": "mo", "megaoctets": "mo"}
TEMPS = {"c": "c", "°c": "c", "celsius": "c", "f": "f", "°f": "f", "fahrenheit": "f",
         "k": "k", "kelvin": "k"}


def _temp(v, de, vers):
    celsius = {"c": v, "f": (v - 32) * 5 / 9, "k": v - 273.15}[de]
    return {"c": celsius, "f": celsius * 9 / 5 + 32, "k": celsius + 273.15}[vers]


def unites(texte):
    t = texte.strip().lstrip("~").strip().lower().replace("°", "°")
    m = re.fullmatch(r"(-?[\d.,]+)\s*([a-zé°]+)\s*(?:en|->|>|vers)\s*([a-zé°]+)", t)
    if not m:
        return []
    try:
        valeur = float(m.group(1).replace(",", "."))
    except ValueError:
        return []
    de, vers = m.group(2).strip(), m.group(3).strip()
    de, vers = ALIAS_UNITES.get(de, de), ALIAS_UNITES.get(vers, vers)
    if de in TEMPS and vers in TEMPS:
        sortie = _temp(valeur, TEMPS[de], TEMPS[vers])
        unite = {"c": "°C", "f": "°F", "k": "K"}[vers]
    else:
        if de not in UNITES or vers not in UNITES:
            return []
        famille, facteur = UNITES[de]
        if UNITES[vers][0] != famille:
            return []
        sortie = round(valeur * facteur / UNITES[vers][1], 4)
        unite = vers
    texte_sortie = f"{nombre_fr(sortie)} {unite}"
    return [resultat("unite", texte_sortie, f"{nombre_fr(valeur)} {de}",
                     "", "unité", action="copy", arg=texte_sortie)]


# ── devises ──────────────────────────────────────────────────────────────────
SIGLES = {"€": "EUR", "$": "USD", "£": "GBP", "¥": "JPY", "chf": "CHF",
          "eur": "EUR", "usd": "USD", "gbp": "GBP", "jpy": "JPY", "cad": "CAD",
          "aud": "AUD", "sek": "SEK", "nok": "NOK", "pln": "PLN", "cny": "CNY"}


def _taux(force=False):
    """Taux BCE via frankfurter, cache 24 h. Rend (taux, date, depuis_cache)."""
    fichier = CACHE / "devises.json"
    if fichier.exists() and not force:
        age = time.time() - fichier.stat().st_mtime
        if age < 86400:
            try:
                d = json.loads(fichier.read_text(encoding="utf-8"))
                return d["rates"], d.get("date", ""), True
            except (json.JSONDecodeError, KeyError):
                pass
    try:
        with urllib.request.urlopen("https://api.frankfurter.app/latest?from=EUR",
                                    timeout=5) as r:
            d = json.loads(r.read().decode("utf-8"))
        CACHE.mkdir(parents=True, exist_ok=True)
        fichier.write_text(json.dumps(d), encoding="utf-8")
        return d["rates"], d.get("date", ""), False
    except Exception:
        if fichier.exists():
            try:
                d = json.loads(fichier.read_text(encoding="utf-8"))
                return d["rates"], d.get("date", ""), True
            except (json.JSONDecodeError, KeyError):
                pass
        return None, "", False


def devises(texte):
    t = texte.strip().lstrip("$").strip().lower()
    m = re.fullmatch(r"([\d.,]+)\s*([€$£¥a-z]*)\s*(?:en|->|>|vers)\s*([€$£¥a-z]*)", t)
    if not m:
        return []
    try:
        valeur = float(m.group(1).replace(",", "."))
    except ValueError:
        return []
    de = SIGLES.get(m.group(2).strip(), m.group(2).strip().upper() or "EUR")
    vers = SIGLES.get(m.group(3).strip(), m.group(3).strip().upper())
    if vers == "":
        return []
    taux, date, cache = _taux()
    if taux is None:
        return [resultat("devise", "Taux indisponibles", "ni cache ni réseau",
                         "", "devise")]
    if de == "EUR":
        facteur = 1.0
    elif de in taux:
        facteur = 1.0 / taux[de]
    else:
        return []
    if vers == "EUR":
        sortie = valeur * facteur
    elif vers in taux:
        sortie = valeur * facteur * taux[vers]
    else:
        return []
    texte_sortie = f"{nombre_fr(round(sortie, 2))} {vers}"
    return [resultat("devise", texte_sortie,
                     f"{nombre_fr(valeur)} {de} · taux du {date}"
                     + (" (cache)" if cache else ""),
                     "", "devise", action="copy", arg=texte_sortie)]


# ── fichiers et contenu ──────────────────────────────────────────────────────
def _rg():
    return shutil.which("rg") or ""


INDEX_FICHIERS_TTL = 300


def _lister_fichiers(rg):
    """Liste des fichiers sous HOME, avec cache disque 5 min pour éviter un scan rg à chaque touche."""
    index = CACHE / "fichiers_index.txt"
    try:
        if index.exists() and (time.time() - index.stat().st_mtime) < INDEX_FICHIERS_TTL:
            return index.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        pass
    sortie = borne([rg, "--files", str(HOME)], timeout=4.0)
    if sortie:
        try:
            CACHE.mkdir(parents=True, exist_ok=True)
            tmp = CACHE / f"fichiers_index.{os.getpid()}.tmp"
            tmp.write_text(sortie, encoding="utf-8")
            os.replace(tmp, index)
        except OSError:
            pass
    return sortie.splitlines()


def fichiers(texte, limite=LIMITE_DEFAUT):
    q = texte.strip().lstrip("/").strip()
    if q == "":
        return []
    rg = _rg()
    if rg == "":
        return [resultat("fichier", "ripgrep absent", "pacman -S ripgrep", "", "fichier")]
    # Sans --hidden : les dossiers cachés (~/.cache, ~/.cargo, ~/.local/share)
    # noieraient les résultats — 642 000 fichiers au lieu de 31 000, et les
    # premiers résultats seraient des README de caches.
    tries = []
    for ligne in _lister_fichiers(rg):
        if ligne == "":
            continue
        chemin = ligne
        nom = os.path.basename(chemin)
        # Le score porte sur le nom sans extension : « README » et « README.md »
        # autrement. C'est ensuite la profondeur qui départage.
        tige = os.path.splitext(nom)[0] or nom
        s = max(score(q, tige), score(q, chemin.replace(str(HOME), "")) - 20)
        if s > 0:
            # À score égal, le fichier le moins enfoui est le plus probable :
            # ~/dev/projet/README.md avant ~/.cargo/registry/.../README.md.
            tries.append((s, chemin.count("/"), chemin, nom))
    top = heapq.nsmallest(limite, tries, key=lambda x: (-x[0], x[1], x[2]))
    return [resultat("fichier", nom, chemin.replace(str(HOME) + "/", "~/"),
                     "", "fichier", action="open", arg=chemin)
            for _, _prof, chemin, nom in top]


# Ce qui n'est jamais une réponse utile : dépendances, caches, historique Git,
# listes de mots. Sans ce filtre, « : bail » ramenait des entrées de wordlists
# btcrecover avant le contrat qui porte le mot.
EXCLUS = re.compile(r"/(site-packages|dist-info|node_modules|\.git|__pycache__|"
                    r"\.cache|\.venv|venv|\.local/share|\.cargo|\.rustup|"
                    r"build|target|wordlists?|\.[a-z]*-cache)/")
# Les documents passent devant : quand on cherche un mot, c'est dans un contrat,
# une attestation ou un tableur qu'on le cherche, pas dans un fichier source.
DOCUMENTS = {".pdf", ".docx", ".odt", ".odp", ".xlsx", ".pptx", ".doc"}
GLOBS_EXCLUS = ["!**/site-packages/**", "!**/dist-info/**", "!**/node_modules/**",
                "!**/.git/**", "!**/__pycache__/**", "!**/.cache/**",
                "!**/.venv/**", "!**/venv/**", "!**/.cargo/**", "!**/.rustup/**",
                "!**/wordlists/**", "!*.lock", "!pnpm-lock.yaml"]


def contenu(texte, limite=6):
    q = texte.strip().lstrip(":").strip()
    if len(q) < 2:
        return []
    rg = _rg()
    if rg == "":
        return []
    # Pas de --max-columns : ripgrep n'affiche alors *aucune* ligne trop longue,
    # donc aucune de celles où le motif apparaît. On borne la sortie à la lecture.
    # `--pre` délègue la lecture des documents à texte_doc.py : sans lui, un PDF
    # ou un DOCX est un binaire et « bail » ne trouve pas le contrat qui le porte.
    # Deux passes, et pas une seule : les documents passent par un préprocesseur
    # (pdftotext, unzip) donc sortent en dernier, et un seul `head` sur le flux
    # commun les coupait — « bail » ne ramenait alors que des fichiers texte.
    pre = Path(__file__).with_name("texte_doc.py")
    exclusions = " ".join(f"-g {shlex.quote(g)}" for g in GLOBS_EXCLUS)
    doc_globs = " ".join(f"-g {shlex.quote(g)}"
                         for g in ("*.pdf", "*.docx", "*.odt", "*.odp"))
    pre_option = (f"--pre {shlex.quote(str(pre))} --pre-glob '*.pdf' "
                  f"--pre-glob '*.docx' --pre-glob '*.odt' --pre-glob '*.odp'")
    base = (f"{shlex.quote(rg)} -n --no-heading --max-count 1 -i -F {shlex.quote(q)} "
            f"{exclusions}")
    commande = (f"{{ {base} {doc_globs} {pre_option} {shlex.quote(str(HOME))} "
                f"2>/dev/null | head -c 300000 ; echo '' ; "
                f"{base} -g '!*.pdf' -g '!*.docx' -g '!*.odt' -g '!*.odp' "
                f"{shlex.quote(str(HOME))} 2>/dev/null | head -c 300000 ; }}")
    sortie = borne_etat(["sh", "-c", commande], timeout=12.0)

    trouves = {}
    for ligne in sortie.splitlines():
        morceaux = ligne.split(":", 2)
        if len(morceaux) < 3:
            continue
        chemin, num, extrait = morceaux
        if chemin in trouves or EXCLUS.search(chemin):
            continue
        trouves[chemin] = (num, extrait)

    def rang(item):
        chemin = item[0]
        extension = os.path.splitext(chemin)[1].lower()
        return (0 if extension in DOCUMENTS else 1, chemin.count("/"), chemin)

    out = []
    for chemin, (num, extrait) in sorted(trouves.items(), key=rang):
        extension = os.path.splitext(chemin)[1].lower()
        etiquette = {".pdf": "pdf", ".docx": "docx", ".odt": "odt", ".odp": "odp",
                     ".xlsx": "xlsx", ".pptx": "pptx"}.get(
                         extension, "ligne" if extension not in (".doc",) else "doc")
        court = chemin.replace(str(HOME) + "/", "~/")
        # Un numéro de ligne n'a pas de sens dans un PDF ou un DOCX : on ne garde
        # que l'extrait, et l'étiquette dit de quelle nature est le fichier.
        emplacement = court if etiquette != "ligne" else f"{court}:{num}"
        out.append(resultat("contenu", os.path.basename(chemin),
                            f"{emplacement} · {extrait.strip()[:90]}",
                            "", etiquette, action="open", arg=chemin))
        if len(out) >= limite:
            break
    return out


# ── presse-papiers, émoji ────────────────────────────────────────────────────
PRESSE_CACHE = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "quickshell" / "vignettes"
PRESSE_EPINGLES = Path(os.environ.get("XDG_CACHE_HOME", str(HOME / ".cache"))) / "quickshell" / "presse_epingles.json"
MAGIES = (b"\x89PNG", b"\xff\xd8", b"GIF8", b"RIFF")


def _octets(commande, taille=96, timeout=3.0):
    """Comme `borne`, mais rend des octets : les types se lisent dans l'en-tête."""
    try:
        p = subprocess.run(commande, capture_output=True, timeout=timeout)
        return p.stdout[:taille]
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return b""


def _type_entree(ident):
    """Nature d'une entrée, lue dans les premiers octets du contenu décodé."""
    tete = _octets(["cliphist", "decode", str(ident)], 16)
    if not tete:
        return "vide"
    if any(tete.startswith(m) for m in MAGIES):
        return "image"
    if b"\x00" in tete:
        return "binaire"
    try:
        texte = tete.decode("utf-8")
    except UnicodeDecodeError:
        return "binaire"
    if re.match(r"^https?://", texte) or "\n" in texte:
        return "lien" if re.match(r"^https?://", texte) else "texte"
    return "texte"


def _vignette(ident):
    """Vignette PNG en RAM, calculée une fois par entrée. Rend un chemin ou ""."""
    try:
        PRESSE_CACHE.mkdir(parents=True, exist_ok=True)
        chemin = PRESSE_CACHE / f"{ident}.png"
        if chemin.exists() and chemin.stat().st_size > 0:
            return str(chemin)
        brut = _octets(["cliphist", "decode", str(ident)], 4_000_000, timeout=5.0)
        if not brut:
            return ""
        # `magick` lit sur l'entrée standard et écrit un PNG mis à l'échelle : une
        # capture d'écran entière pèse plusieurs mégaoctets, la vignette 96 px
        # suffit à reconnaître ce qu'on cherche.
        r = subprocess.run(["magick", "-", "-thumbnail", "96x96", f"png:{chemin}"],
                           input=brut, capture_output=True, timeout=8.0)
        return str(chemin) if r.returncode == 0 and chemin.exists() else ""
    except (OSError, subprocess.SubprocessError):
        return ""


IMG_EXT = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp")


def _uri_image(texte):
    """Un fichier copié depuis un gestionnaire de fichiers arrive en texte :
    `file:///chemin/image.png`. Ce n'est pas une image binaire, mais c'en est une
    pour l'utilisateur — on rend le chemin pour pouvoir en faire une vignette."""
    if not texte:
        return None
    premiere = texte.strip().splitlines()[0].strip() if texte.strip() else ""
    if premiere.startswith("file://"):
        chemin = premiere[len("file://"):]
    elif premiere.startswith("x-special/gnome-copied-files"):
        lignes = texte.strip().splitlines()
        if len(lignes) < 2 or not lignes[1].startswith("file://"):
            return None
        chemin = lignes[1][len("file://"):]
    elif premiere.startswith("x-special/nautilus-clipboard"):
        lignes = texte.strip().splitlines()
        if len(lignes) < 3 or not lignes[2].startswith("file://"):
            return None
        chemin = lignes[2][len("file://"):]
    elif premiere.startswith("/"):
        # Chemin nu (copié depuis un terminal, ou entrée ancienne de cliphist) :
        # même intention qu'une URI, même traitement.
        chemin = premiere
    else:
        return None
    chemin = chemin.strip()
    if not chemin.lower().endswith(IMG_EXT):
        return None
    return chemin if Path(chemin).is_file() else None


def _vignette_fichier(chemin, ident):
    """Vignette d'un fichier image copié depuis un gestionnaire de fichiers."""
    try:
        PRESSE_CACHE.mkdir(parents=True, exist_ok=True)
        cible = PRESSE_CACHE / f"f{ident}.png"
        if cible.exists() and cible.stat().st_size > 0:
            return str(cible)
        r = subprocess.run(["magick", chemin, "-thumbnail", "96x96", f"png:{cible}"],
                           capture_output=True, timeout=8.0)
        return str(cible) if r.returncode == 0 and cible.exists() else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def _epingles():
    try:
        d = json.loads(PRESSE_EPINGLES.read_text(encoding="utf-8"))
        return d if isinstance(d, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def _ecrire_epingles(d):
    try:
        PRESSE_EPINGLES.parent.mkdir(parents=True, exist_ok=True)
        PRESSE_EPINGLES.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError:
        pass


def presse_epingler(ident, texte=""):
    """Conserve une entrée au-delà de la rotation de cliphist."""
    if not ident:
        return "identifiant manquant"
    brut = _octets(["cliphist", "decode", str(ident)], 4_000_000, timeout=5.0)
    if not brut:
        return "contenu illisible"
    d = _epingles()
    if any(t[:60] == brut[:60] for t in ()):      # garde-fou de forme, jamais vrai
        return ""
    # L'épingle survit à cliphist : on conserve donc l'image entière, pas
    # seulement sa vignette. Sans cela, une capture épinglée devenait une vignette
    # de 96 px une fois l'original évincé.
    epingles_dir = PRESSE_CACHE.parent / "epingles"
    try:
        epingles_dir.mkdir(parents=True, exist_ok=True)
        (epingles_dir / f"{ident}.bin").write_bytes(brut)
    except OSError:
        pass
    vign = PRESSE_CACHE / f"{ident}.png"
    d[str(ident)] = {
        "texte": texte[:200],
        "type": _type_entree(ident),
        "vignette": str(vign) if vign.exists() else "",
        "original": str(epingles_dir / f"{ident}.bin") if (epingles_dir / f"{ident}.bin").exists() else "",
        "quand": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    _ecrire_epingles(d)
    return f"épinglé : {ident}"


def presse_desepingler(ident):
    d = _epingles()
    if d.pop(str(ident), None) is not None:
        _ecrire_epingles(d)
        return f"désépinglé : {ident}"
    return "cette entrée n'était pas épinglée"


def presse_supprimer(ident):
    """Efface une entrée précise. `cliphist delete` lit des sélections sur
    l'entrée standard, au format « id<TAB>aperçu » : on lui donne l'id seul,
    suffisant pour qu'il retrouve la ligne."""
    if not ident:
        return "identifiant manquant"
    # `cliphist delete` sort en 0 même quand l'id n'existe pas : on vérifie avant.
    if not any(l.split("\t", 1)[0] == str(ident)
               for l in borne(["cliphist", "list"], timeout=2.0).splitlines()):
        return f"entrée {ident} introuvable"
    try:
        r = subprocess.run(["cliphist", "delete"], input=f"{ident}\t\n",
                           capture_output=True, text=True, timeout=5)
    except (subprocess.TimeoutExpired, OSError):
        return "suppression impossible"
    d = _epingles()
    if d.pop(str(ident), None) is not None:
        _ecrire_epingles(d)
        for reste in (PRESSE_CACHE / f"{ident}.png", PRESSE_CACHE.parent / "epingles" / f"{ident}.bin"):
            try:
                reste.unlink()
            except OSError:
                pass
    return f"entrée {ident} supprimée" if r.returncode == 0 else "suppression refusée"


def presse_vider():
    """Vide l'historique complet, épingles comprises. Action destructive : c'est
    au launcher de demander une confirmation, pas au service."""
    try:
        r = subprocess.run(["cliphist", "wipe"], capture_output=True, timeout=10)
    except (subprocess.TimeoutExpired, OSError):
        return "purge impossible"
    _ecrire_epingles({})
    try:
        for f in PRESSE_CACHE.glob("*.png"):
            f.unlink()
    except OSError:
        pass
    return "historique vidé" if r.returncode == 0 else "purge refusée"


def presse(texte, limite=8):
    """Historique cliphist, enrichi : type reconnu, vignette pour les images,
    épinglés d'abord. L'action reste « copy » pour tout : c'est le contrat que le
    launcher applique déjà, et le type sert à décrire l'entrée, pas à changer son
    comportement au clic."""
    q = texte.strip().lstrip('"').strip().lower()
    epingles = _epingles()
    out = []

    for ident, infos in epingles.items():
        libelle = infos.get("texte") or f"entrée {ident}"
        if q and q not in libelle.lower():
            continue
        # Même règle que pour les entrées vivantes : un lien épinglé s'ouvre.
        action, cible = ("copy", ident)
        if infos.get("type") == "lien":
            action, cible = "open-url", libelle
        out.append(resultat("presse", libelle[:80], f"épinglé · {infos.get('type', '')}",
                            infos.get("vignette") or "", "presse", action=action, arg=cible))

    for ligne in borne(["cliphist", "list"], timeout=2.0).splitlines():
        if "\t" not in ligne:
            continue
        ident, apercu = ligne.split("\t", 1)
        apercu = apercu.strip().replace("\n", " ")
        if ident in epingles:
            continue
        if q and q not in apercu.lower():
            continue
        nature = _type_entree(ident)
        vignette = _vignette(ident) if nature == "image" else ""
        # Fichier image copié dans Thunar/Nautilus : le texte est une URI.
        if nature == "texte":
            chemin = _uri_image(apercu)
            if chemin:
                nature = "image (fichier)"
                vignette = _vignette_fichier(chemin, ident)
                apercu = Path(chemin).name
        libelle = apercu[:80] or f"({nature})"
        # cliphist nomme une image « [[ binary data 1 KiB png 300x200 ]] » : lisible
        # par personne. On en tire ce qui compte — le format et les dimensions.
        if nature == "image":
            m = re.search(r"\b(png|jpeg|jpg|webp|gif)\s+(\d+)x(\d+)", apercu, re.I)
            if m:
                libelle = f"capture {m.group(2)}×{m.group(3)}"
            else:
                libelle = "image copiée"
        detail = f"entrée {ident} · {nature}"
        # Ce que le contenu appelle : un lien s'ouvre, un chemin existant s'ouvre,
        # tout le reste se copie. L'ancien comportement copiait même une URL, ce
        # qui obligeait à coller puis recliquer.
        action, cible = "copy", ident
        if nature == "lien":
            action, cible = "open-url", apercu.split()[0] if apercu.split() else ""
        elif nature == "texte":
            premier = apercu.split()[0] if apercu.split() else ""
            if premier.startswith("/") and Path(premier).exists():
                action, cible = "open-url", premier
        out.append(resultat("presse", libelle, detail, vignette, "presse",
                            action=action, arg=cible))
        if len(out) >= limite:
            break
    return out


FR_EN = {
    "coeur": "red heart", "cœur": "red heart", "amour": "love", "rire": "joy",
    "sourire": "smile", "clin": "wink", "triste": "sad", "pleure": "cry",
    "colere": "angry", "fete": "party", "feu": "fire", "eau": "water",
    "soleil": "sun", "lune": "moon", "etoile": "star", "nuage": "cloud",
    "pluie": "rain", "neige": "snow", "chat": "cat", "chien": "dog",
    "souris": "mouse", "oiseau": "bird", "poisson": "fish", "fleur": "flower",
    "arbre": "tree", "feuille": "leaf", "pomme": "apple", "pain": "bread",
    "cafe": "coffee", "biere": "beer", "vin": "wine", "pizza": "pizza",
    "voiture": "car", "velo": "bike", "fusee": "rocket", "avion": "airplane",
    "maison": "house", "livre": "book", "crayon": "pencil", "musique": "music",
    "ordinateur": "computer", "telephone": "phone", "horloge": "clock",
    "cle": "key", "cadeau": "gift", "argent": "money", "outil": "wrench",
    "coche": "check", "croix": "cross", "attention": "warning", "info": "information",
    "ok": "ok", "stop": "stop", "fichier": "file", "dossier": "folder",
    "drapeau": "flag", "coeur rouge": "red heart", "pouce": "thumb",
}

_EMOJI = None


def emoji(texte, limite=9):
    global _EMOJI
    if _EMOJI is None:
        chemin = Path(__file__).with_name("emoji.json")
        try:
            _EMOJI = json.loads(chemin.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            _EMOJI = []
    q = texte.strip().lstrip(";").strip().lower()
    if q == "":
        return []
    # Les noms de la base sont en anglais : on accepte les mots français les plus
    # courants, sinon « ; coeur » ne rendrait rien.
    variantes = {q}
    if q in FR_EN:
        variantes = {q, FR_EN[q]}
    tries = []
    for e in _EMOJI:
        nom = e.get("name", "")
        mots = " ".join(e.get("keywords", []))
        s = 0
        for v in variantes:
            local = max(score(v, nom), score(v, mots) - 10,
                        score(v, e.get("category", "")) - 20)
            if local > 0 and nom == v:
                local += 60          # le nom exact d'abord
            elif local > 0 and nom.startswith(v):
                local += 20
            s = max(s, local)
        if s > 0:
            tries.append((s - len(nom) / 50.0, e))
    top = heapq.nlargest(limite, tries, key=lambda x: x[0])
    return [resultat("emoji", e["emoji"] + "  " + e.get("name", ""),
                     e.get("category", ""), "", "émoji",
                     action="copy", arg=e["emoji"])
            for _, e in top]


# ── processus ────────────────────────────────────────────────────────────────
def processus(texte, limite=8):
    q = texte.strip().lstrip("%").strip()
    sortie = borne(["ps", "-eo", "pid,pcpu,pmem,comm,args", "--sort=-pcpu"],
                   timeout=2.0)
    out = []
    for ligne in sortie.splitlines()[1:]:
        morceaux = ligne.split(None, 4)
        if len(morceaux) < 5:
            continue
        pid, cpu, mem, comm, args = morceaux
        if comm in ("ps",) or args.startswith("ps -eo") or pid == str(os.getpid()):
            continue
        if q and not (q.lower() in comm.lower() or q.lower() in args.lower()):
            continue
        out.append(resultat("processus", comm,
                            f"pid {pid} · {cpu}% cpu · {mem}% mem · {args[:70]}",
                            "", f"{cpu}% cpu", action="kill", arg=pid))
        if len(out) >= limite:
            break
    return out


# ── signets ──────────────────────────────────────────────────────────────────
def signets(texte, limite=8):
    q = texte.strip().lstrip("*").strip()
    racine = HOME / ".mozilla" / "firefox"
    candidats = sorted(racine.glob("*/places.sqlite"),
                       key=lambda p: p.stat().st_mtime, reverse=True) if racine.exists() else []
    if not candidats:
        return [resultat("signet", "Aucun profil Firefox", "~/.mozilla absent",
                         "", "signet")]
    base = candidats[0]
    try:
        con = sqlite3.connect(f"file:{base}?mode=ro&immutable=1", uri=True, timeout=2.0)
        req = ("SELECT b.title, p.url FROM moz_bookmarks b "
               "JOIN moz_places p ON p.id = b.fk "
               "WHERE b.type = 1 AND p.url NOT LIKE 'place:%' "
               "AND (? = '' OR b.title LIKE ? OR p.url LIKE ?) "
               "ORDER BY b.dateAdded DESC LIMIT ?")
        motif = f"%{q}%"
        lignes = con.execute(req, (q, motif, motif, 60)).fetchall()
        con.close()
    except sqlite3.Error:
        return []
    tries = []
    for titre, url in lignes:
        s = max(score(q, titre or ""), score(q, url or "") - 10) if q else 1
        if s > 0:
            tries.append((s, titre or url, url))
    top = heapq.nlargest(limite, tries, key=lambda x: x[0])
    return [resultat("signet", titre or url, url, "", "signet",
                     action="open-url", arg=url)
            for _, titre, url in top]


# ── aide ─────────────────────────────────────────────────────────────────────
def aide():
    return [resultat("aide", f"{sym}  {libelle}", exemple, "", "aide",
                     action="prefill", arg=exemple)
            for sym, _kind, libelle, exemple, _phrase in PREFIXES]


def phrases_aide():
    return [{"symbole": sym, "kind": k, "libelle": lib, "exemple": ex, "phrase": ph}
            for sym, k, lib, ex, ph in PREFIXES]



# ── aperçu d'un fichier ──────────────────────────────────────────────────────
# Un seul appel rend tout ce qu'il faut pour le volet : type, métadonnées, texte
# ou url d'image. Le QML n'a plus qu'à rendre — aucune logique de fichier côté
# interface, et c'est testable en CLI.
IMAGES = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".svg", ".avif", ".ico"}
LIGNES, COLONNES = 46, 104


def taille_lisible(octets):
    for unite in ("o", "ko", "Mo", "Go", "To"):
        if octets < 1024 or unite == "To":
            return f"{octets:.0f} {unite}" if unite == "o" else f"{octets:.1f} {unite}"
        octets /= 1024.0


def texte_document(chemin):
    """Texte d'un PDF, DOCX, ODT ou ODP, via texte_doc.py.

    C'est le même chemin que la recherche dans le contenu : il mémorise le texte
    extrait en RAM, donc l'aperçu d'un document déjà cherché est immédiat.
    """
    outil = Path(__file__).with_name("texte_doc.py")
    try:
        r = subprocess.run([sys.executable, str(outil), str(chemin)],
                           capture_output=True, text=True, timeout=10, errors="replace")
    except (OSError, subprocess.TimeoutExpired):
        return ""
    brut = [ligne.replace("\f", "") for ligne in r.stdout.splitlines()]
    return "\n".join(l[:COLONNES] for l in brut[:LIGNES])


def apercu(chemin):
    p = Path(os.path.expanduser(chemin))
    if not p.exists():
        return {"ok": False, "type": "absent", "meta": {}, "texte": "",
                "message": "fichier absent"}
    try:
        st = p.stat()
    except OSError as e:
        return {"ok": False, "type": "illisible", "texte": "", "message": str(e)}
    meta = {"nom": p.name,
            "taille": taille_lisible(st.st_size),
            "date": time.strftime("%d/%m %H:%M", time.localtime(st.st_mtime)),
            "chemin": str(p).replace(str(HOME) + "/", "~/")}

    if p.is_dir():
        try:
            entrees = sorted(os.listdir(p))
        except OSError as e:
            return {"ok": False, "type": "illisible", "texte": "", "message": str(e)}
        visibles = [e + ("/" if (p / e).is_dir() else "") for e in entrees[:40]]
        return {"ok": True, "type": "dossier", "meta": dict(meta, taille=f"{len(entrees)} entrées"),
                "texte": "\n".join(visibles)}
    if p.suffix.lower() in IMAGES:
        return {"ok": True, "type": "image", "meta": meta, "url": "file://" + str(p),
                "texte": ""}
    if p.suffix.lower() in (".pdf", ".docx", ".odt", ".odp"):
        est_pdf = p.suffix.lower() == ".pdf"
        texte = texte_document(p)
        if texte.strip() == "":
            return {"ok": True, "type": "pdf" if est_pdf else "bureautique",
                    "meta": meta, "texte": "",
                    "message": ("aucun texte — scan sans couche texte ?" if est_pdf
                                else "aucun texte extrait")}
        return {"ok": True, "type": "pdf" if est_pdf else "bureautique",
                "meta": meta, "texte": texte, "note": "texte extrait"}

    try:
        with p.open("rb") as f:
            debut = f.read(8192)
    except OSError as e:
        return {"ok": False, "type": "illisible", "texte": "", "message": str(e)}
    # Un octet nul dans l'en-tête = binaire. On ne prétend pas deviner mieux.
    if b"\x00" in debut and p.suffix.lower() not in (".pdf",):
        return {"ok": True, "type": "binaire", "meta": meta, "texte": "",
                "message": "contenu binaire"}
    texte = debut.decode("utf-8", "replace")
    tronque = st.st_size > len(debut) * 2
    if tronque:
        try:
            with p.open("r", encoding="utf-8", errors="replace") as f:
                texte = "".join(f.readline() for _ in range(LIGNES))
        except OSError:
            pass
    lignes = [l[:COLONNES] for l in texte.splitlines()[:LIGNES]]
    return {"ok": True, "type": "texte", "meta": meta, "texte": "\n".join(lignes),
            "tronque": tronque or len(texte.splitlines()) > LIGNES}


# ── dispatch ─────────────────────────────────────────────────────────────────
DISPATCH = {
    "commande": None,   # géré par le QML (mode `>` historique)
    "calc": calcul,
    "fichiers": fichiers,
    "contenu": contenu,
    "presse": presse,
    "emoji": emoji,
    "unites": unites,
    "devises": devises,
    "processus": processus,
    "signets": signets,
    "aide": lambda _t: aide(),
    # Épinglage : appelé par le launcher sur SHIFT+P. Entrée du contrat inchangée
    # (une action, un argument), pour ne pas ajouter un second vocabulaire.
    "presse_epingler": lambda t: [resultat("presse", presse_epingler(t.strip(), ""),
                                           "épinglé", "", "presse")],
    "presse_desepingler": lambda t: [resultat("presse", presse_desepingler(t.strip()),
                                              "désépinglé", "", "presse")],
}


def traiter(requete, limite=LIMITE_DEFAUT):
    q = requete or ""
    if q.strip() == "":
        return {"ok": True, "prefix": "", "kind": "", "results": []}
    sym = q[0]
    for prefixe, kind, *_ in PREFIXES:
        if prefixe != sym:
            continue
        fonction = DISPATCH.get(kind)
        if fonction is None:          # `>` reste au QML
            return {"ok": True, "prefix": sym, "kind": kind, "results": [],
                    "qml": True}
        try:
            res = fonction(q[1:], limite) if kind in ("fichiers", "contenu", "presse",
                                                     "emoji", "processus", "signets") \
                else fonction(q[1:])
        except TypeError:
            res = fonction(q[1:])
        except Exception as e:        # un prestataire ne casse pas le launcher
            return {"ok": False, "prefix": sym, "kind": kind,
                    "error": f"{type(e).__name__}: {e}", "results": []}
        for r in res:
            # L'aide décrit un préfixe : sa pastille montre celui dont elle parle,
            # pas « ? » répété onze fois.
            r.setdefault("sym", sym)
        return {"ok": True, "prefix": sym, "kind": kind, "results": res,
                "interrompu": INTERROMPU["valeur"]}
    return {"ok": True, "prefix": "", "kind": "", "results": []}


def main(argv):
    requete, limite = "", LIMITE_DEFAUT
    i = 1
    while i < len(argv):
        # Épinglage depuis le launcher (SHIFT+P) ou le terminal : ces deux options
        # n'ont pas besoin du vocabulaire des préfixes, elles agissent sur un id.
        if argv[i] == "--supprimer" and i + 1 < len(argv):
            print(presse_supprimer(argv[i + 1]))
            return 0
        if argv[i] == "--vider":
            print(presse_vider())
            return 0
        if argv[i] == "--epingler" and i + 1 < len(argv):
            print(presse_epingler(argv[i + 1], ""))
            return 0
        if argv[i] == "--desepingler" and i + 1 < len(argv):
            print(presse_desepingler(argv[i + 1]))
            return 0
        if argv[i] == "--query" and i + 1 < len(argv):
            requete = argv[i + 1]
            i += 2
        elif argv[i] == "--limit" and i + 1 < len(argv):
            try:
                limite = max(1, min(20, int(argv[i + 1])))
            except ValueError:
                pass
            i += 2
        elif argv[i] == "--apercu" and i + 1 < len(argv):
            print(json.dumps(apercu(argv[i + 1]), ensure_ascii=False))
            return 0
        elif argv[i] == "--aide":
            print(json.dumps({"ok": True, "prefixes": phrases_aide()},
                             ensure_ascii=False))
            return 0
        else:
            requete = argv[i]
            i += 1
    print(json.dumps(traiter(requete, limite), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
