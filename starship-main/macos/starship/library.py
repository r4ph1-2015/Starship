from pathlib import Path
import json
import shutil
import uuid

APP_SUPPORT = Path.home() / "Library" / "Application Support" / "Starship"
WALLPAPER_DIR = APP_SUPPORT / "Wallpapers"
STATE_FILE = APP_SUPPORT / "state.json"
VIDEO_EXTS = {".mp4", ".mov", ".m4v", ".webm", ".avi", ".mkv"}

APP_SUPPORT.mkdir(parents=True, exist_ok=True)
WALLPAPER_DIR.mkdir(parents=True, exist_ok=True)

class Library:
    def _load(self):
        try:
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {}

    def _save(self, state):
        STATE_FILE.write_text(json.dumps(state, indent=2), encoding="utf-8")

    def import_video(self, source):
        source = Path(source)
        if not source.exists():
            raise FileNotFoundError(source)
        if source.suffix.lower() not in VIDEO_EXTS:
            raise ValueError(f"Unsupported video format: {source.suffix}")

        destination = WALLPAPER_DIR / f"{source.stem}-{uuid.uuid4().hex[:8]}{source.suffix.lower()}"
        shutil.copy2(source, destination)
        self.set_active(destination)
        return destination

    def set_active(self, wallpaper):
        state = self._load()
        state["active"] = Path(wallpaper).name
        self._save(state)

    def active(self):
        name = self._load().get("active")
        if not name:
            return None
        path = WALLPAPER_DIR / name
        return path if path.exists() else None
