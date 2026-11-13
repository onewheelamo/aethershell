# AetherShell

[Lire en français](../README.md)

A desktop environment for [Hyprland](https://hyprland.org), featuring an island-style bar, modular panels, desktop widgets, and everyday tools, written in QML/Qt and powered by [Quickshell](https://quickshell.org).

> **Note:** AetherShell does not claim to reinvent the wheel or establish itself as a standard. It is simply a personal desktop environment among others, still young and actively evolving (`0.2.x` cycle), designed to fit a daily workflow and refine over experience.

---

## 1. Overview

Rather than a simple bar theme, AetherShell brings together the visual and utility components of the graphical session:

* **Main Bar & Modular Capsule**: two switchable modes, configurable on the fly:
  * *Classic*: a three-island layout (left, center, right) enclosed in a shared capsule with customizable separation transparency and morphed bar-aligned panels (`PanneauSurface`).
  * *Dynamic Island*: a single 3-state interactive central pill — compact at rest (time, mini-player, integrated OSD), expanded on hover (applets, full MPRIS controls, calendar), and morphed on click into a **5-tab interactive panel** (*Controls*, *Media & Sound*, *Alerts & Tasks*, *System & Network*, *Appearance*).
* **Optional Secondary Bars**: support for a bottom bar and vertical side bars following the same component architecture.
* **Unified Configuration Panel**: accessible via a hotkey (`SUPER + SHIFT + H`, while `SUPER + H` toggles the Dynamic Island panel) or by middle-clicking any applet. Allows tuning appearance (palettes, blurs, corner radii, opacity), favorite applications, displays, idle timeout (`hypridle`), autostart, and local secrets, with live hot-reloading without restarting the session.
* **Dockable Desktop Widgets**: draggable blocks (tasks, system monitor, weather, music, clock, agent...) configurable and filterable by virtual workspace (middle-click to restrict a widget to one or more workspaces).
* **Reactive Audio Visualizer**: discreet integration of a native PipeWire waveform (`pwscope`) or spectral bars (`cava`), with automatic sleep after ten seconds of silence to conserve GPU/CPU resources.
* **Task Tracking & Hermes Integration**: local Markdown checklist management (`- [ ]`) with a graphical file picker and an optional monitoring switch delegating checked tasks to the Hermes agent via a background worker.
* **Integrated Graphical Selectors**: modal sheets drawn directly within the shell surface ([`SelecteurDossier.qml`](../dev/SelecteurDossier.qml), [`SelecteurFichier.qml`](../dev/SelecteurFichier.qml)), bypassing the limitation of traditional Wayland dialogs that would open beneath the overlay layer surface.
* **Login Screen Manager (SDDM)**: configuration of the Astronaut theme and Qylock variants from the panel, with a safe preview launcher isolating tests on a dedicated workspace (`workspace 99`) to never freeze the active session.

---

## 2. Deployment & Updates

### One-Line Install or Update

```sh
curl -fsSL https://raw.githubusercontent.com/onewheelamo/aethershell/master/install.sh | bash
```

[`install.sh`](../install.sh) handles everything: it detects the distribution from `/etc/os-release` (Arch or Fedora), clones the repository or fast-forwards it if already present, backs up the environment, and deploys the shell. The exact same command serves for initial installation and subsequent updates.

Options: `--dir PATH` (default: `$AETHERSHELL_DIR`, otherwise `~/dev/quickshell_todo` if present, otherwise `~/dev/aethershell`), `--arch` / `--fedora` to override the target instead of reading `/etc/os-release`, `--branche NAME`, `--check` (status only, without deploying), `--no-deploy`, `--help`. With the one-line curl command, pass them after `bash -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/onewheelamo/aethershell/master/install.sh | bash -s -- --check
```

The panel tracks the same version as the script: "Displays & System" → "Shell Updates" displays the deployed version, the version published on GitHub, and available actions (check now, update in a terminal, copy the one-liner for another machine). `core/version.json` is written on every deployment, and `core/maj_shell.py` queries GitHub only once every **280 minutes** — between checks, it serves from cache, avoiding unnecessary network calls when opening the panel.

### Manual Deployment

Deployment is handled by [`install.sh`](../install.sh), compatible with **Arch Linux** and **Fedora** (auto-detected via `/etc/os-release`):

```sh
# Check required dependencies without installing anything
./install.sh --deps

# Pre-flight diff analysis (Repository ➜ Live system) without modifications
./install.sh --diff

# Full deployment with prior backup (tarball + fine-grained snapshot)
./install.sh --arch    # or ./install.sh --fedora

# Fast deployment without new backup (when the state is already archived)
./install.sh --deploy-only
```

### Strict Protection of Local Data

Deployment never blindly replaces live files:
* **Protected local states**: `style_vars.json`, `bar_applets.json`, `widgets.json`, `autostart.json`, `todo.json`, `secrets.json`, etc. are never overwritten if they already exist on the target machine.
* **Custom Hyprland configuration**: `binds.lua`, `input.lua`, `general.lua`, and hardware profiles remain authoritative. In case of differences with the repository, a comparative `.upstream` copy is created without touching the active file.
* **Granular safety net**: each deployment creates a backup `.tar.gz` archive and an uncompressed mirror snapshot under `~/.config/backups_env/snapshots/<timestamp>/` with a SHA-256 fingerprint table (`manifest.json`), enabling single-file restoration when needed (`./install.sh --restore-file <path>`).

---

### Multi-User and Multi-Machine Support

Nothing in the repository hardcodes a username, personal folder, or machine hostname: AetherShell installs under any user account, and `./install.sh` always writes to the `$HOME` of the user running it.

Paths are constructed using variables, never hardcoded:

| Context | To use |
|---|---|
| shell | `"$HOME"`, `"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"` |
| Python | `Path.home()`, `os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"` |
| QML | `Quickshell.env("HOME")`, `Quickshell.env("XDG_RUNTIME_DIR")` |
| systemd unit | `%h` (unit directive) |

`python3 dev/core/neutralite.py` inspects **tracked** files: it flags any `/home/<name>` that is not a placeholder, as well as the username and machine hostname. The deployment pre-flight runs it and displays a warning. A line may include an explicit exception — `neutralite:ok — <reason>` — for intentional compatibility.

---

## 3. Prerequisites

* **Compositor**: [Hyprland](https://hyprland.org) 0.57 or newer (modular Lua configuration);
* **UI Engine**: [Quickshell](https://quickshell.org) 0.3.2 or newer;
* **Icon Font**: `0xProto Nerd Font` (installer provided in `dev/core/install_fonts.sh`);
* **System Dependencies**: listed by distribution in [`dev/dependencies.txt`](../dev/dependencies.txt) (`rofi`, `matugen`, `wireplumber`, `NetworkManager`, `cava`, etc.).

---

## 4. Project Structure

```
install.sh            # Unified script: install, update, pre-flight checks, deployment, and backups
dev/
├── core/             # Python services (network, disks, tasks, Hermes, file listing...)
├── widgets/          # Desktop components (clock, todo, system, weather...)
├── hypr_modular/     # Modular Hyprland configuration in Lua
├── hyprquickpaper/   # Wallpaper engine and palette management
├── sddm/             # Scripts and helpers for SDDM login screen
├── systemd/          # User systemd units (quickshell.service...)
└── *.qml             # Quickshell surfaces (bar, panel, popups, selectors...)
```

---

## 5. Acknowledgments & Code Borrowing

AetherShell did not emerge in a vacuum: it builds upon bricks, concepts, and code snippets from other open source projects with compelling approaches. Many thanks to the following authors for their work shared under open licenses (notably the [Noctalia Community Plugins](https://github.com/noctalia-dev/community-plugins) collection, under the MIT license):

| Component / Concept | Original Author | Description |
|---|---|---|
| [Visualizer+](https://github.com/noctalia-dev/community-plugins/tree/main/visualizerp) | **al3x** | PipeWire capture engine in C (`pwscope.c`), compiled locally to feed the audio waveform. |
| [Agentik](https://github.com/noctalia-dev/community-plugins/tree/main/agentik) | **notfinaldev** | Principles of non-blocking agent status polling, process/session matching, and state management. |
| [USB Manager](https://github.com/noctalia-dev/community-plugins/tree/main/usb-manager) | **Marco Ziliani** | Hardware polling architecture reading directly from `sysfs` and `udev` without requiring a heavy resident daemon. |
| [To Do](https://github.com/noctalia-dev/community-plugins/tree/main/todo) | **nightwatch75** | Initial inspiration for decoupling the bar applet and desktop widget for task lists. |
| [NVTOP](https://github.com/noctalia-dev/community-plugins/tree/main/nvtop) | **tordex** | On-demand system monitoring principle (process spawned only when the view is opened). |
| [Wallpaper Depth](https://github.com/noctalia-dev/official-plugins/tree/main/wallpaper_depth) | **noctalia** | Visual immersion concept for islands using depth maps (Depth Anything V2). |
| [WallpaperFx.qml (`pocket-dots`)](https://github.com/diegoMalagrida/pocket-dots) | **diegoMalagrida** | Shader-based wallpaper transitions (`WallpaperFx.qml` / `wallfx.frag`: organic 4 px cell spread and seamless `awww` handover). |
| **Quickshell & Hyprland** | **outfoxxed & vaxerski** | For these two major projects that make building a modern, performant Wayland shell possible. |

---

## 6. License

AetherShell is distributed under the MIT license — see the [`LICENSE`](../LICENSE) file for details.
