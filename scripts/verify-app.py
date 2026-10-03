#!/usr/bin/env python3
"""Reject bundles that only work on the build machine."""
import plistlib
import base64
import re
import subprocess
import sys
from pathlib import Path


def output(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(app):
    contents = app / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    require(info["CFBundleIdentifier"] == "com.mscno.QuadcastRGBApp", "Unexpected bundle identifier")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", info["CFBundleShortVersionString"]), "Invalid version")
    require(info["LSUIElement"] is True, "Expected menu bar application")
    require(info["LSMinimumSystemVersion"] == "26.0", "Expected macOS 26 minimum")
    require(bool(info.get("NSMicrophoneUsageDescription")), "Missing microphone usage description")
    require(info.get("SUFeedURL") == "https://github.com/mscno/QuadcastRGB2S/releases/latest/download/appcast.xml", "Invalid update feed")
    require(len(base64.b64decode(info.get("SUPublicEDKey", ""), validate=True)) == 32, "Invalid update public key")
    require(info.get("SURequireSignedFeed") is True and info.get("SUVerifyUpdateBeforeExtraction") is True, "Unsigned updater configuration")
    sparkle = contents / "Frameworks/Sparkle.framework/Versions/B/Sparkle"
    require(sparkle.is_file(), "Missing embedded Sparkle")
    binary = contents / "MacOS" / info["CFBundleExecutable"]
    library = contents / "Frameworks/libhidapi.0.dylib"
    require(library.is_file() and not library.is_symlink(), "Missing embedded hidapi")
    for file in (binary, library):
        require(output("lipo", "-archs", str(file)).strip() == "arm64", f"Unexpected architecture: {file}")
        for line in output("otool", "-L", str(file)).splitlines()[1:]:
            dependency = line.strip().split(" (", 1)[0]
            if dependency.startswith(("/System/Library/", "/usr/lib/")):
                continue
            require(dependency in ("@rpath/libhidapi.0.dylib", "@rpath/Sparkle.framework/Versions/B/Sparkle"), f"Nonportable dependency: {dependency}")
        require("/opt/homebrew" not in output("otool", "-l", str(file)), "Homebrew load path remains")
        require("/usr/local" not in output("otool", "-l", str(file)), "Local load path remains")
    output("codesign", "--verify", "--deep", "--strict", str(app))
    signature = output("codesign", "-d", "--entitlements", "-", "--xml", str(app))
    start = signature.find("<?xml")
    require(start >= 0, "Missing signed entitlements")
    end = signature.find("</plist>", start) + len("</plist>")
    entitlements = plistlib.loads(signature[start:end].encode())
    require(entitlements.get("com.apple.security.device.audio-input") is True, "Missing audio input entitlement")
    return binary


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify-app.py /path/to/QuadcastRGBApp.app")
    verify(Path(sys.argv[1]))
    print("Verified arm64 bundle and self-contained dependencies.")
