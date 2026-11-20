use std::fs::{File, OpenOptions};
use std::io;
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};

/// Verrou inter-processus `flock(LOCK_EX)` sur un fichier voisin `<cible>.verrou`.
/// Ne jamais supprimer le fichier `.verrou` ni verrouiller le JSON cible directement.
pub struct FileLock {
    _file: File,
}

impl FileLock {
    pub fn acquire(target: &Path) -> io::Result<Self> {
        let mut lock_os = target.as_os_str().to_os_string();
        lock_os.push(".verrou");
        let lock_path = PathBuf::from(lock_os);
        if let Some(parent) = lock_path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let file = OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .open(&lock_path)?;
        let ret = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) };
        if ret != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Self { _file: file })
    }
}

impl Drop for FileLock {
    fn drop(&mut self) {
        unsafe {
            libc::flock(self._file.as_raw_fd(), libc::LOCK_UN);
        }
    }
}
