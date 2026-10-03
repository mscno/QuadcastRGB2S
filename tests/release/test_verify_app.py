"""Portable-bundle failures must be caught before notarization/upload."""
import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("verify_app", ROOT / "scripts/verify-app.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BundleTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.app = Path(temp.name) / "QuadcastRGBApp.app"
        self.contents = self.app / "Contents"
        (self.contents / "MacOS").mkdir(parents=True)
        (self.contents / "Frameworks").mkdir()
        (self.contents / "Frameworks/libhidapi.0.dylib").write_bytes(b"fixture")
        (self.contents / "MacOS/QuadcastRGBApp").write_bytes(b"fixture")
        self.info = dict(CFBundleIdentifier="com.mscno.QuadcastRGBApp", CFBundleShortVersionString="1.0.0",
                         LSUIElement=True, LSMinimumSystemVersion="26.0", CFBundleExecutable="QuadcastRGBApp", NSMicrophoneUsageDescription="Opt-in microphone test")
        self.write_info()
        self.arch = "arm64"
        self.dependency = "@rpath/libhidapi.0.dylib"
        self.load_commands = ""
        self.entitlements = {"com.apple.security.device.audio-input": True}

    def write_info(self):
        (self.contents / "Info.plist").write_bytes(plistlib.dumps(self.info))

    def command(self, *args):
        if args[0] == "lipo":
            return self.arch
        if args[0] == "otool" and args[1] == "-L":
            return "fixture:\n\t" + self.dependency + " (compatibility version 1.0.0)\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n"
        if args[0] == "otool":
            return self.load_commands
        if args[0] == "codesign" and args[1] == "-d":
            return "Executable=/fixture/app\n" + plistlib.dumps(self.entitlements).decode()
        return ""

    def verify(self):
        with patch.object(module, "output", self.command):
            return module.verify(self.app)

    def test_self_contained_bundle_passes(self):
        self.assertEqual(self.verify(), self.contents / "MacOS/QuadcastRGBApp")

    def test_homebrew_dependency_is_rejected(self):
        self.dependency = "/opt/homebrew/opt/hidapi/lib/libhidapi.0.dylib"
        with self.assertRaisesRegex(ValueError, "Nonportable"):
            self.verify()

    def test_homebrew_rpath_is_rejected(self):
        self.load_commands = "LC_RPATH path /opt/homebrew/lib"
        with self.assertRaisesRegex(ValueError, "Homebrew load path"):
            self.verify()

    def test_missing_embedded_library_is_rejected(self):
        (self.contents / "Frameworks/libhidapi.0.dylib").unlink()
        with self.assertRaisesRegex(ValueError, "Missing embedded"):
            self.verify()

    def test_wrong_architecture_is_rejected(self):
        self.arch = "x86_64"
        with self.assertRaisesRegex(ValueError, "architecture"):
            self.verify()

    def test_mismatched_bundle_id_is_rejected(self):
        self.info["CFBundleIdentifier"] = "another.app"
        self.write_info()
        with self.assertRaisesRegex(ValueError, "identifier"):
            self.verify()

    def test_missing_microphone_usage_is_rejected(self):
        self.info.pop("NSMicrophoneUsageDescription")
        self.write_info()
        with self.assertRaisesRegex(ValueError, "microphone usage"):
            self.verify()

    def test_missing_audio_input_entitlement_is_rejected(self):
        self.entitlements = {}
        with self.assertRaisesRegex(ValueError, "audio input entitlement"):
            self.verify()
