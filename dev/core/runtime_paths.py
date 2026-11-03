"""Per-user private locations for caches and small state files.

Fixed names in the world-writable /tmp are avoided (symlink attacks, fs.protected_regular
PermissionError when another user created the file). $XDG_RUNTIME_DIR is used when
available, with ~/.cache/quickshell as a fallback.
"""
import os


def runtime_dir():
    base = os.environ.get("XDG_RUNTIME_DIR")
    if base and os.path.isdir(base) and os.access(base, os.W_OK):
        path = os.path.join(base, "quickshell-session")
    else:
        path = os.path.join(os.path.expanduser("~/.cache"), "quickshell")
    try:
        os.makedirs(path, mode=0o700, exist_ok=True)
        os.chmod(path, 0o700)
    except OSError:
        pass
    return path


def runtime_path(name):
    return os.path.join(runtime_dir(), name)
