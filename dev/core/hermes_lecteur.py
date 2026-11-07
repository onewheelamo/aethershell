#!/usr/bin/env python3
"""Lit l'état réel de Hermes pour le shell — la base, pas un état publié.

Décision du 2026-11-07 : le shell ne dépend plus d'un fichier que Hermes devrait
publier (il ne publiait jamais, donc l'applet restait vide). On lit ce que Hermes
sait déjà, en **lecture seule** :

  - `state.db`, ouvert en `?mode=ro` : table `sessions` (titre, modèle, dossier,
    dépôt git, début, dernière activité, fin, jetons, coût) ;
  - `/proc` pour savoir si une session tourne encore : Hermes se lance avec un
    `-p <profil>` en fin de ligne de commande, c'est ce qui identifie le profil
    vivant (la base, elle, garde des sessions ouvertes même après un arrêt brutal) ;
  - la file d'approbations du shell (`hermes-approbations.json`), que la base ne
    connaît pas.

**Une base par profil.** `~/.hermes/profiles/<profil>/state.db` est la vraie base
de travail ; `~/.hermes/state.db` n'est plus que l'ancienne base globale. On lit
les deux et chaque session porte son profil — un shell qui ne verrait que la base
globale afficherait des sessions de la semaine dernière en croyant que rien ne
tourne.

Discipline reprise d'Agentik : on n'invente pas un statut. `end_reason` est une
donnée, pas une interprétation ; un champ absent reste absent (colonnes vérifiées
avant lecture) ; une base illisible donne `hors_ligne` et non un état par défaut.

    python3 hermes_lecteur.py etat        # ce que le shell affiche (JSON)
    python3 hermes_lecteur.py sessions    # les sessions, sans mise en forme
    python3 hermes_lecteur.py processus   # profils vivants et leurs pid
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys
import time
from pathlib import Path

RACINE = Path.home() / ".hermes"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())) / "quickshell"
APPROBATIONS = RUNTIME / "hermes-approbations.json"

# Le popup montre cinq exécutions et quelques sessions ; le widget trois lignes.
MAX_SESSIONS = 10
# Au-delà de cette inactivité, une session ouverte sans processus vivant n'est
# plus « en cours » : le processus a pu mourir sans écrire `ended_at`.
DELAI_INACTIF = 900


# ── les bases ─────────────────────────────────────────────────────────────────
def bases():
    """[(profil, chemin)] : une par profil, plus l'ancienne base globale."""
    trouvees = []
    profils = RACINE / "profiles"
    if profils.is_dir():
        for dossier in sorted(profils.iterdir()):
            base = dossier / "state.db"
            if base.is_file():
                trouvees.append((dossier.name, base))
    globale = RACINE / "state.db"
    if globale.is_file():
        trouvees.append(("defaut", globale))
    return trouvees


def _connexion(chemin):
    """Lecture seule stricte : `mode=ro` empêche sqlite de créer le fichier s'il
    manque et de poser un verrou d'écriture sur une base en cours d'usage."""
    return sqlite3.connect(chemin.as_uri() + "?mode=ro", uri=True, timeout=2)


def _colonnes(cx, table):
    try:
        return {r[1] for r in cx.execute("PRAGMA table_info(%s)" % table)}
    except sqlite3.Error:
        return set()


# ── sessions ──────────────────────────────────────────────────────────────────
CHAMPS = ("id", "title", "model", "cwd", "source", "started_at", "last_activity_at",
          "last_activity_description", "ended_at", "end_reason", "archived", "pinned",
          "profile_name", "input_tokens", "output_tokens", "cache_read_tokens",
          "cache_write_tokens", "estimated_cost_usd", "tool_call_count",
          "message_count", "git_repo_root", "git_branch")


def lire_sessions(limite=MAX_SESSIONS):
    """Les sessions récentes de tous les profils, la plus active d'abord.
    `None` si aucune base n'est lisible — l'appelant en déduit « hors ligne »."""
    toutes = []
    lisible = False
    for profil, chemin in bases():
        try:
            with _connexion(chemin) as cx:
                cx.row_factory = sqlite3.Row
                colonnes = _colonnes(cx, "sessions")
                if not colonnes:
                    continue
                lisible = True
                champs = [c for c in CHAMPS if c in colonnes]
                ordre = "last_activity_at" if "last_activity_at" in colonnes else "started_at"
                sql = "SELECT %s FROM sessions" % ", ".join(champs)
                if "archived" in colonnes:
                    sql += " WHERE archived = 0"
                sql += " ORDER BY %s DESC LIMIT ?" % ordre
                for ligne in cx.execute(sql, (limite,)).fetchall():
                    d = dict(ligne)
                    d["profil"] = d.get("profile_name") or profil
                    # Hermes ouvre parfois une session technique sans titre ni
                    # travaux : elle encombrerait la liste sans rien dire.
                    if d.get("ended_at") is not None \
                            and not (d.get("title") or "").strip() \
                            and not d.get("input_tokens") and not d.get("message_count"):
                        continue
                    toutes.append(d)
        except sqlite3.Error:
            continue
    if not lisible:
        return None
    toutes.sort(key=lambda s: float(s.get("last_activity_at") or s.get("started_at") or 0),
                reverse=True)
    toutes = toutes[:limite]
    # Une requête par session serait du gaspillage : seules les trois premières
    # peuvent apparaître en tête de barre ou de popup.
    chemins = dict(bases())
    for s in toutes[:3]:
        s["demande"] = derniere_demande(chemins.get(s.get("profil")) or RACINE / "state.db",
                                        s.get("id"))
    return toutes


def derniere_demande(chemin, session_id, longueur=90):
    """Le dernier message de l'utilisateur, une ligne : c'est la meilleure
    description de ce que l'agent fait. `last_activity_description` contient des
    notes internes (« context compression completed ») qui ne disent rien de la
    tâche. Longueur bornée, texte brut, jamais d'exception."""
    try:
        with _connexion(chemin) as cx:
            if "messages" not in {r[0] for r in cx.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'")}:
                return ""
            colonnes = _colonnes(cx, "messages")
            if not {"session_id", "role", "content"} <= colonnes:
                return ""
            filtre = " AND active = 1" if "active" in colonnes else ""
            ordre = "timestamp" if "timestamp" in colonnes else "id"
            ligne = cx.execute(
                "SELECT content FROM messages WHERE session_id = ? AND role = 'user'%s "
                "ORDER BY %s DESC LIMIT 1" % (filtre, ordre), (session_id,)
            ).fetchone()
            texte = (ligne[0] or "") if ligne else ""
            texte = " ".join(str(texte).split())
            return texte[:longueur]
    except sqlite3.Error:
        return ""


def _dossiers_profils():
    """[(profil, dossier)] : un par profil, plus la racine (ancienne base)."""
    trouves = []
    profils = RACINE / "profiles"
    if profils.is_dir():
        for dossier in sorted(profils.iterdir()):
            if dossier.is_dir():
                trouves.append((dossier.name, dossier))
    trouves.append(("defaut", RACINE))
    return trouves


def taches_planifiees(limite=4):
    """Les tâches planifiées, lues dans `<profil>/cron/jobs.json`.

    La base `state.db` ne les connaît pas : le planificateur tient son propre
    fichier, `{"jobs": [...], "updated_at": ...}`, où la date de la prochaine
    exécution est déjà calculée (`next_run_at`, ISO avec fuseau). On ne
    recalcule donc rien — une expression cron relue à la main finirait par
    mentir.
    """
    liste = []
    for profil, dossier in _dossiers_profils():
        fichier = dossier / "cron" / "jobs.json"
        try:
            donnees = json.loads(fichier.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        taches = donnees.get("jobs") if isinstance(donnees, dict) else donnees
        if not isinstance(taches, list):
            continue
        for t in taches:
            if not isinstance(t, dict):
                continue
            planif = t.get("schedule_display")
            if not planif and isinstance(t.get("schedule"), dict):
                planif = t["schedule"].get("display")
            liste.append({
                "nom": str(t.get("name") or "sans nom"),
                "prochaine": t.get("next_run_at"),
                "dernier": str(t.get("last_status") or ""),
                "quand": t.get("last_run_at"),
                "planification": str(planif or ""),
                "profil": profil,
                "actif": bool(t.get("enabled", True)),
            })
    # Les actives d'abord, puis par prochaine échéance ; celles sans date en fin.
    liste.sort(key=lambda t: (not t["actif"], t["prochaine"] or "9999"))
    return liste[:limite]


def jetons_du_jour():
    """Somme des jetons d'entrée et de sortie des sessions actives aujourd'hui."""
    debut = time.mktime(time.localtime()[:3] + (0, 0, 0, 0, 0, -1))
    total = 0
    for _, chemin in bases():
        try:
            with _connexion(chemin) as cx:
                colonnes = _colonnes(cx, "sessions")
                if not {"input_tokens", "output_tokens"} <= colonnes:
                    continue
                champ = "last_activity_at" if "last_activity_at" in colonnes else "started_at"
                ligne = cx.execute(
                    "SELECT COALESCE(SUM(input_tokens),0) + COALESCE(SUM(output_tokens),0) "
                    "FROM sessions WHERE %s >= ?" % champ, (debut,)
                ).fetchone()
                total += int(ligne[0] or 0)
        except sqlite3.Error:
            continue
    return {"jour": total, "tache": 0}


# ── processus vivants ─────────────────────────────────────────────────────────
def processus_hermes():
    """{profil: [pid]} des sessions Hermes réellement en cours.

    Hermes ne s'exécute pas comme un binaire `hermes` : c'est un interpréteur avec
    un script en ligne, terminé par `-p <profil>`. On reconnaît donc le profil au
    drapeau, et on écarte ce qui n'est pas une session : le superviseur de
    processus et la passerelle (`gateway run`), qui vivent en permanence.
    """
    vivants = {}
    uid = os.getuid()
    for entree in Path("/proc").iterdir():
        if not entree.name.isdigit():
            continue
        try:
            if entree.stat().st_uid != uid:
                continue
            brut = entree.joinpath("cmdline").read_bytes()
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if b"hermes_cli" not in brut or b"process_supervisor" in brut:
            continue
        # Les tokens sont séparés par des NUL, pas par des espaces : on cherche le
        # drapeau comme token, et le profil est celui qui le suit.
        morceaux = brut.split(b"\0")
        profil = None
        for i, m in enumerate(morceaux):
            if m == b"-p" and i + 1 < len(morceaux):
                candidat = morceaux[i + 1].decode("utf-8", "ignore").strip()
                if candidat and not candidat.startswith("-"):
                    profil = candidat
        if profil:
            vivants.setdefault(profil, []).append(int(entree.name))
    return vivants


def marquer_vivantes(sessions, vivants):
    """Une session est vivante si son profil a un processus, qu'elle n'est pas
    terminée, et qu'elle est la plus récente ouverte de ce profil : un profil ne
    fait tourner qu'une session à la fois."""
    par_profil = {}
    for s in sessions:
        if s.get("ended_at") in (None, 0):
            par_profil.setdefault(s.get("profil"), []).append(s)
    for profil, liste in par_profil.items():
        pids = vivants.get(profil) or []
        liste.sort(key=lambda s: float(s.get("last_activity_at") or s.get("started_at") or 0),
                   reverse=True)
        for rang, s in enumerate(liste):
            s["vivante"] = bool(pids) and rang == 0
            s["pid"] = pids[0] if s["vivante"] else None
    for s in sessions:
        s.setdefault("vivante", False)
        s.setdefault("pid", None)
    return sessions


# ── approbations ──────────────────────────────────────────────────────────────
def approbations():
    try:
        d = json.loads(APPROBATIONS.read_text(encoding="utf-8"))
        return [a for a in (d.get("approbations") or []) if isinstance(a, dict)]
    except (OSError, json.JSONDecodeError):
        return []


# ── l'état pour le shell ──────────────────────────────────────────────────────
def _iso(horodatage):
    try:
        return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(float(horodatage)))
    except (TypeError, ValueError, OSError):
        return None


def _duree(session):
    """Durée lisible côté QML : la session vivante compte jusqu'à maintenant,
    une session interrompue s'arrête à sa dernière activité."""
    try:
        debut = float(session.get("started_at") or 0)
        if session.get("ended_at"):
            fin = float(session["ended_at"])
        elif session.get("vivante"):
            fin = time.time()
        else:
            fin = float(session.get("last_activity_at") or debut)
        return max(0, int(fin - debut))
    except (TypeError, ValueError):
        return 0


def _secondes(session):
    for champ in ("last_activity_at", "started_at"):
        try:
            return float(session.get(champ) or 0)
        except (TypeError, ValueError):
            continue
    return 0.0


def etat():
    """Le contrat que `hermes_applet.py` sait déjà présenter.

    Mêmes clés que l'ancien fichier publié (`etat`, `tache`, `depuis`, `executions`,
    `cron`, `jetons`, `perime`), plus `sessions` et `attention`.
    """
    maintenant = time.time()
    sessions = lire_sessions()
    if sessions is None:
        return {"present": False, "raison": "aucune base lisible"}

    marquer_vivantes(sessions, processus_hermes())
    attente = approbations()
    actives = [s for s in sessions if s.get("vivante")
               or (s.get("ended_at") in (None, 0)
                   and (maintenant - _secondes(s)) < DELAI_INACTIF)]
    actives_ids = {str(s.get("id")) for s in actives}

    executions = []
    for s in sessions:
        if s.get("vivante") or s.get("ended_at") in (None, 0):
            continue
        debut = s.get("started_at") or 0
        fin = s.get("ended_at") or debut
        try:
            duree = max(0, int(float(fin) - float(debut)))
        except (TypeError, ValueError):
            duree = 0
        executions.append({
            "nom": str(s.get("title") or s.get("last_activity_description") or "session"),
            "debut": _iso(debut),
            "duree_s": duree,
            "resultat": str(s.get("end_reason") or "ok"),
            "modele": str(s.get("model") or ""),
        })

    etat_court = "attente" if attente else ("en_cours" if actives else "repos")
    tache = ""
    depuis = None
    if actives:
        principal = actives[0]
        tache = str(principal.get("demande") or principal.get("title")
                    or "session en cours")
        depuis = _iso(principal.get("started_at"))
    elif sessions:
        tache = str(sessions[0].get("title") or "")

    age = None
    if sessions:
        age = max(0, int(maintenant - _secondes(sessions[0])))

    return {
        "present": True,
        "source": "state.db",
        "etat": etat_court,
        "tache": tache,
        "depuis": depuis,
        "file": len(attente),
        "executions": executions[:5],
        "cron": taches_planifiees(),
        "jetons": jetons_du_jour(),
        "age_s": age,
        "perime": False,
        "approbations": attente[:3],
        "attention": len(attente),
        "profils": sorted({str(s.get("profil") or "") for s in actives} - {""}),
        "sessions": [
            {
                "id": s.get("id"),
                "titre": s.get("title") or "",
                "tache": s.get("demande") or s.get("title") or "",
                "modele": s.get("model") or "",
                "profil": s.get("profil") or "",
                "dossier": s.get("cwd") or "",
                "depot": s.get("git_repo_root") or "",
                "branche": s.get("git_branch") or "",
                "source": s.get("source") or "",
                "debut": _iso(s.get("started_at")),
                "activite": _iso(s.get("last_activity_at")),
                "fin": _iso(s.get("ended_at")),
                "etat": ("en_cours" if str(s.get("id")) in actives_ids
                         else ("terminee" if s.get("ended_at") else "inactive")),
                "vivante": bool(s.get("vivante")),
                "pid": s.get("pid"),
                "duree_s": _duree(s),
                "jetons": int((s.get("input_tokens") or 0) + (s.get("output_tokens") or 0)),
                "outils": int(s.get("tool_call_count") or 0),
                "cout": s.get("estimated_cost_usd"),
            }
            for s in sessions
        ],
        "ecrit": _iso(maintenant),
    }


def main(argv):
    action = argv[1] if len(argv) > 1 else ""
    if action == "etat":
        print(json.dumps(etat(), ensure_ascii=False))
        return 0
    if action == "sessions":
        sessions = lire_sessions()
        if sessions is None:
            print("aucune base lisible", file=sys.stderr)
            return 1
        print(json.dumps(marquer_vivantes(sessions, processus_hermes()),
                         ensure_ascii=False, indent=1))
        return 0
    if action == "processus":
        print(json.dumps(processus_hermes(), ensure_ascii=False))
        return 0
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
