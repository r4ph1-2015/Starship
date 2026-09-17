from pathlib import Path
from datetime import datetime
import traceback

LOG_DIR = Path.home() / "Library" / "Logs" / "Starship"
LOG_FILE = LOG_DIR / "starship.log"
LOG_DIR.mkdir(parents=True, exist_ok=True)

def log(message):
    line = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}"
    try:
        with LOG_FILE.open("a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass
    print(line, flush=True)

def log_exception(prefix, exc):
    log(f"{prefix}: {exc!r}")
    try:
        with LOG_FILE.open("a", encoding="utf-8") as f:
            traceback.print_exc(file=f)
    except Exception:
        pass
