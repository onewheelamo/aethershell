#!/usr/bin/env python3
"""Applet « Homelab » : ce qui tourne, ce qui est tombé, et qui répond.

Quatre sources :
  • unités systemd en échec (système et session) — `systemctl --failed` ;
  • hôtes à surveiller, listés dans core/homelab.json :
        {"hotes": [{"nom": "nas", "url": "nas.local"}, ...]}
  • une instance Proxmox, si elle est déclarée dans ce même fichier :
        {"proxmox": {"url": "https://pve.lan:8006", "verifier_tls": false}}
    Le jeton d'API vit dans secrets.json (section « proxmox »), jamais ici : le
    fichier de configuration peut être lu, comparé et copié sans fuite.

Sans fichier de configuration, l'applet se rabat sur les deux premières sources :
il dit déjà quelque chose d'utile, sans rien inventer sur un parc qu'il ne connaît
pas.

    python3 homelab_applet.py [--force]
"""
from __future__ import annotations

import json
import os
import re
import ssl
import subprocess
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applet_contrat import compact, presenter, sortir  # noqa: E402

BASE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(BASE, "homelab.json")
SECRETS = os.path.join(BASE, "secrets.json")
DELAI = 4
DELAI_API = 5


def _config():
    try:
        with open(CONFIG, "r", encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return {}
    return d if isinstance(d, dict) else {}


def _secrets():
    """La section « proxmox » de secrets.json, ou un dict vide.

    Le jeton n'est jamais lu ailleurs, jamais imprimé, jamais recopié dans un
    fichier de configuration : seul le appel HTTP le porte.
    """
    try:
        with open(SECRETS, "r", encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return {}
    section = d.get("proxmox") if isinstance(d, dict) else None
    return section if isinstance(section, dict) else {}



def _run(cmd, timeout=DELAI):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def unites_en_echec():
    n = 0
    noms = []
    for portee in (["--failed"], ["--user", "--failed"]):
        sortie = _run(["systemctl"] + portee + ["--no-legend", "--plain"])
        for ligne in sortie.splitlines():
            morceaux = ligne.split()
            if not morceaux:
                continue
            n += 1
            if len(noms) < 5:
                noms.append(morceaux[0])
    return {"nombre": n, "noms": noms}


def _ping(cible):
    """Latence en ms si la cible répond, None sinon. Un ping, un aller-retour."""
    res = _run(["ping", "-c", "1", "-W", "1", cible], timeout=3)
    m = re.search(r"(?:time|temps)[=<]([\d.]+)\s*ms", res)
    if not m:
        m = re.search(r"rtt[^=]*=\s*[\d.]+/([\d.]+)/", res)
    return round(float(m.group(1))) if m else None


def hotes():
    """Ceux du fichier de configuration, avec leur latence ou leur absence.

    Les pings partent **en parallèle** : séquentiels, cinq machines éteintes
    bloquaient le relevé une seconde chacune, donc dix secondes d'attente dans
    un sous-processus que la barre interroge à chaque cadence.
    """
    conf = _config()

    cibles = []
    for h in (conf.get("hotes") or []):
        if not isinstance(h, dict):
            continue
        nom = str(h.get("nom") or h.get("url") or "").strip()
        cible = str(h.get("url") or h.get("nom") or "").strip()
        if not cible:
            continue
        cibles.append((nom, cible))
    if not cibles:
        return []

    with ThreadPoolExecutor(max_workers=min(8, len(cibles))) as pool:
        latences = list(pool.map(lambda paire: _ping(paire[1]), cibles))

    return [{
        "nom": nom,
        "url": cible,
        "joignable": latence is not None,
        "latence_ms": latence,
    } for (nom, cible), latence in zip(cibles, latences)]


def _api(base, chemin, jeton, verifier_tls, timeout=DELAI_API, methode="GET"):
    """Appel à l'API Proxmox ; renvoie (données, erreur lisible)."""
    url = base.rstrip("/") + "/api2/json" + chemin
    req = urllib.request.Request(url, headers={
        "Authorization": "PVEAPIToken=" + jeton,
        "Accept": "application/json",
    }, method=methode, data=b"" if methode == "POST" else None)
    contexte = None
    if not verifier_tls:
        # Proxmox sert un certificat auto-signé par défaut : exiger la
        # vérification rendrait l'applet muet sur toute installation standard.
        contexte = ssl._create_unverified_context()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=contexte) as rep:
            return json.loads(rep.read().decode("utf-8")).get("data"), None
    except urllib.error.HTTPError as e:
        if e.code == 401:
            return None, "jeton refusé"
        if e.code == 403:
            # Authentifié mais sans le droit : c'est une ACL à poser sur le
            # serveur, pas un identifiant faux — la distinction évite de chercher
            # longtemps du côté du shell.
            return None, "droits insuffisants"
        return None, "HTTP " + str(e.code)
    except (urllib.error.URLError, OSError, ValueError) as e:
        return None, "injoignable" if isinstance(e, (urllib.error.URLError, OSError)) else "réponse illisible"


def proxmox():
    """État du nœud et des machines virtuelles, lus sur l'API Proxmox.

    Rien n'est interrogé si l'URL ou le jeton manquent : l'applet ne doit pas
    afficher une erreur pour une source qu'on ne lui a pas donnée.
    """
    conf = _config().get("proxmox") or {}
    url = str(conf.get("url") or "").strip()
    if not url:
        return {}

    sec = _secrets()
    # L'identifiant du jeton n'est pas un secret : il vit dans homelab.json.
    # secrets.json reste accepté en repli pour les configurations antérieures.
    ident = str(conf.get("token_id") or sec.get("token_id") or "").strip()
    secret = str(sec.get("token_secret") or "").strip()
    if not ident or not secret:
        return {"configure": True, "url": url, "erreur": "jeton absent"}

    jeton = ident + "=" + secret
    verifier = bool(conf.get("verifier_tls", False))

    noeuds, erreur = _api(url, "/nodes", jeton, verifier)
    if erreur:
        return {"configure": True, "url": url, "erreur": erreur}

    vms, erreur_vm = _api(url, "/cluster/resources?type=vm", jeton, verifier)
    if erreur_vm:
        vms = []

    out = {"configure": True, "url": url, "erreur": None, "noeuds": [], "vms": []}

    for n in (noeuds or []):
        if not isinstance(n, dict):
            continue
        maxmem = float(n.get("maxmem") or 0)
        mem = float(n.get("mem") or 0)
        out["noeuds"].append({
            "nom": str(n.get("node") or ""),
            "en_ligne": str(n.get("status") or "") == "online",
            "cpu": round(100 * float(n.get("cpu") or 0)),
            "ram": round(100 * mem / maxmem) if maxmem > 0 else None,
            "ram_go": round(mem / 1073741824, 1) if mem else None,
            "ram_max_go": round(maxmem / 1073741824, 1) if maxmem > 0 else None,
            "uptime_j": round(float(n.get("uptime") or 0) / 86400, 1),
        })

    for v in (vms or []):
        if not isinstance(v, dict):
            continue
        etat = str(v.get("status") or "")
        # Les gabarits et les machines stoppées volontairement ne sont pas des
        # incidents : seules les machines « running » et « stopped » comptent.
        if v.get("template"):
            continue
        # Les mêmes champs servent au widget et au popup : ce que
        # `/cluster/resources?type=vm` rend déjà (cpu, mémoire, disque, uptime)
        # évite une requête par invité.
        maxmem = float(v.get("maxmem") or 0)
        mem = float(v.get("mem") or 0)
        maxdisk = float(v.get("maxdisk") or 0)
        disque = float(v.get("disk") or 0)
        out["vms"].append({
            "id": v.get("vmid"),
            "nom": str(v.get("name") or ""),
            "type": str(v.get("type") or ""),       # lxc = CT, qemu = VM
            "etat": etat,
            "noeud": str(v.get("node") or ""),
            "cpu": round(100 * float(v.get("cpu") or 0)),
            "ram": round(100 * mem / maxmem) if maxmem > 0 else None,
            "ram_go": round(mem / 1073741824, 1),
            "ram_max_go": round(maxmem / 1073741824, 1),
            "disque_go": round(disque / 1073741824, 1),
            "disque_max_go": round(maxdisk / 1073741824, 1),
            "uptime_j": round(float(v.get("uptime") or 0) / 86400, 1),
        })

    en_cours = [v for v in out["vms"] if v["etat"] == "running"]
    out["en_cours"] = len(en_cours)
    out["total"] = len(out["vms"])
    out["ct"] = len([v for v in out["vms"] if v["type"] == "lxc"])
    out["vm"] = len([v for v in out["vms"] if v["type"] == "qemu"])

    # Aucun invité alors que les nœuds répondent : le jeton s'authentifie mais ne
    # voit rien. Proxmox filtre `/cluster/resources` par permission, donc une ACL
    # absente donne une liste vide — pas une erreur. On le dit, sinon l'applet
    # affiche « 0 » et laisse croire à un homelab vide.
    if not out["vms"]:
        droits, _ = _api(url, "/access/permissions", jeton, verifier)
        out["droits"] = "aucun" if isinstance(droits, dict) and not droits else "limites"
        if out["droits"] == "aucun":
            out["aide"] = ("pveum acl modify / --tokens '" + ident
                           + "' --roles PVEAuditor")
    return out


VERBES = ("start", "stop", "shutdown", "reboot")


def agir(verbe, genre, noeud, vmid):
    """Action sur un invité : CT (`lxc`) ou VM (`qemu`).

    `reboot` demande au système invité de redémarrer proprement, `shutdown` de
    s'arrêter proprement, `stop` coupe net. Un jeton qui n'a que VM.Audit reçoit un
    403 : c'est VM.PowerMgmt qui autorise l'action, et le message le dit.
    """
    conf = _config().get("proxmox") or {}
    url = str(conf.get("url") or "").strip()
    sec = _secrets()
    ident = str(conf.get("token_id") or sec.get("token_id") or "").strip()
    secret = str(sec.get("token_secret") or "").strip()
    if not url or not ident or not secret:
        return {"ok": False, "message": "Proxmox non configuré"}
    if genre not in ("lxc", "qemu") or verbe not in VERBES or not noeud or not vmid:
        return {"ok": False, "message": "cible invalide"}

    chemin = f"/nodes/{noeud}/{genre}/{int(vmid)}/status/{verbe}"
    _, erreur = _api(url, chemin, ident + "=" + secret,
                     bool(conf.get("verifier_tls", False)), methode="POST")
    if erreur:
        return {"ok": False, "message": erreur, "chemin": chemin}
    return {"ok": True, "message": verbe + " demandé", "chemin": chemin}


def analyser():
    unites = unites_en_echec()
    h = hotes()
    pve = proxmox()

    injoignables = [x for x in h if not x["joignable"]]
    pve_erreur = (pve or {}).get("erreur")
    alerte = bool(injoignables) or unites["nombre"] > 0 or bool(pve_erreur)

    if injoignables:
        valeur = str(len(injoignables))
        libelle = "hôte(s) injoignable(s)"
    elif unites["nombre"] > 0:
        valeur = str(unites["nombre"])
        libelle = "service(s) en échec"
    elif pve_erreur:
        valeur = "!"
        libelle = "Proxmox " + str(pve_erreur)
    elif pve.get("configure") and pve.get("droits") == "aucun":
        # Le jeton s'authentifie mais ne voit rien : ce n'est pas « parc vide »,
        # et une valeur vide laisserait croire que l'applet est cassé.
        valeur = "!"
        libelle = "Proxmox sans droits"
    elif pve.get("configure") and pve.get("total", 0) > 0:
        valeur = str(pve.get("en_cours", 0)) + "/" + str(pve.get("total", 0))
        # « invités » : le parc mêle des CT et des VM, et l'ancien libellé « VM »
        # annonçait 18 machines alors que quinze sont des conteneurs.
        libelle = "invités"
    else:
        valeur = ""
        libelle = ""

    barres = []
    if pve and pve.get("configure"):
        if pve_erreur:
            barres.append({
                "cle": "proxmox", "nom": "Proxmox", "icone": "cloud-check",
                "valeur": 0, "remplissage": 0, "texte": str(pve_erreur),
                "niveau": "critique", "alerte": True,
            })
        elif pve.get("droits") == "aucun":
            barres.append({
                "cle": "proxmox", "nom": "Proxmox", "icone": "cloud-check",
                "valeur": 0, "remplissage": 0, "texte": "sans droits",
                "niveau": "attention", "alerte": True,
            })
        elif pve.get("total", 0) > 0:
            pct = round(100 * int(pve.get("en_cours", 0)) / max(1, int(pve.get("total", 1))))
            barres.append({
                "cle": "proxmox", "nom": "Proxmox", "icone": "cloud-check",
                "valeur": pct, "remplissage": pct,
                "texte": str(pve.get("en_cours", 0)) + "/" + str(pve.get("total", 0)),
                # Une machine arrêtée est souvent volontaire : la barre vire à
                # l'orange, mais l'applet ne passe pas en alerte pour autant.
                "niveau": "attention" if pct < 100 else "ok",
                "alerte": False,
            })
    if h:
        joignables = [x for x in h if x["joignable"]]
        pct = round(100 * len(joignables) / len(h))
        barres.append({
            "cle": "hotes", "nom": "Hôtes", "icone": "cloud-check",
            "valeur": pct, "remplissage": pct,
            "texte": str(len(joignables)) + "/" + str(len(h)),
            "niveau": "critique" if pct < 100 else "ok",
            "alerte": pct < 100,
        })

    return {
        "ok": True,
        "compact": compact(valeur, libelle, alerte, barres=barres or None),
        "detail": {"unites": unites, "hotes": h, "proxmox": pve},
        "applet": "homelab",
        "icone": "cloud-check",
        "alerte": alerte,
    }


def main(argv):
    # Mode action, pour le widget : `--action reboot --type lxc --node hoth --vmid 100`.
    # Il ne produit pas de contrat d'applet, juste un verdict JSON — l'applet
    # garde une seule forme de sortie.
    if "--action" in argv:
        def valeur(nom, defaut=""):
            if nom in argv:
                i = argv.index(nom)
                if i + 1 < len(argv):
                    return argv[i + 1]
            return defaut
        verdict = agir(valeur("--action"), valeur("--type", "lxc"),
                       valeur("--node"), valeur("--vmid"))
        print(json.dumps(verdict, ensure_ascii=False))
        return 0 if verdict.get("ok") else 1

    donnees = analyser()
    presenter(donnees, "homelab", "cloud-check", donnees["compact"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
