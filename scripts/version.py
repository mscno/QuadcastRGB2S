#!/usr/bin/env python3
"""One semver shared by all Xcode configurations/targets."""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
project = root / "QuadcastRGBApp/QuadcastRGBApp.xcodeproj/project.pbxproj"
versions = set(re.findall(r"MARKETING_VERSION = ([^;]+);", project.read_text()))
if len(versions) != 1 or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", next(iter(versions), "")):
    raise SystemExit("All MARKETING_VERSION values must contain the same numeric x.y.z version.")
print(versions.pop())
