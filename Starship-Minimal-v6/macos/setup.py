from setuptools import setup

APP = ["starship/__main__.py"]

OPTIONS = {
    "argv_emulation": False,
    "packages": ["starship"],
    "plist": {
        "CFBundleName": "Starship",
        "CFBundleDisplayName": "Starship",
        "CFBundleIdentifier": "com.starship.wallpaper",
        "CFBundleShortVersionString": "1.0.4",
        "CFBundleVersion": "5",
        "LSUIElement": True,
    },
}

setup(
    app=APP,
    name="Starship",
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
