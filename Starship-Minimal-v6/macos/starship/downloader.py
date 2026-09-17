from pathlib import Path
import tempfile
import requests
from .library import Library, VIDEO_EXTS

def download_video(url):
    url = url.strip()
    if not url.startswith(("http://", "https://")):
        raise ValueError("Enter a valid http:// or https:// video URL.")

    suffix = Path(url.split("?", 1)[0]).suffix.lower()
    if suffix not in VIDEO_EXTS:
        suffix = ".mp4"

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as f:
        temp = Path(f.name)

    try:
        with requests.get(url, stream=True, timeout=60, headers={"User-Agent": "Starship/1.0"}) as response:
            response.raise_for_status()
            content_type = response.headers.get("content-type", "").lower()
            if "text/html" in content_type:
                raise ValueError("This URL returned a webpage, not a video. Paste the direct video file URL.")

            with temp.open("wb") as out:
                for chunk in response.iter_content(1024 * 1024):
                    if chunk:
                        out.write(chunk)

        return Library().import_video(temp)
    finally:
        try:
            temp.unlink()
        except FileNotFoundError:
            pass
