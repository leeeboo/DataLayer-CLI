#!/usr/bin/env python3
"""Keep accepted Apple appearance differences distinct from release regressions."""
import contextlib
import hashlib
import io
import json
import os
import pathlib
import tarfile
import tempfile
import unittest
import zipfile
from unittest.mock import patch

import compare_export_fixture as comparison
import package_portable_release as packaging


class ReleaseChecks(unittest.TestCase):
    def compare(self, portable_visual_failure=False, audio_failure=False, fixture_mismatch=False):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for platform in ["macos", "linux", "windows"]:
                folder = root / ("export-" + platform)
                folder.mkdir()
                (folder / "report.json").write_text(json.dumps({"fixture": platform if fixture_mismatch else "shared"}))

            def score(left, right, alpha=False):
                differs = left.parent.name == "export-macos" or portable_visual_failure
                return {"mean": .98 if differs else 1, "minimum": .97 if differs else 1}

            with patch.object(comparison, "similarity", score), patch.object(comparison, "audio", return_value={
                "correlation": .8 if audio_failure else 1, "rms_delta": 0,
            }), contextlib.redirect_stdout(io.StringIO()):
                result = comparison.compare(root, root / "comparison.json")
            return result, json.loads((root / "comparison.json").read_text())

    def testAppleAppearanceDifferencesAreReportedAndAccepted(self):
        passed, report = self.compare()
        self.assertTrue(passed)
        self.assertEqual(len(report["visual_differences"]), 8)
        self.assertFalse(report["comparisons"]["macos-linux"]["prores-4444"]["visual_parity_required"])
        self.assertTrue(report["comparisons"]["linux-windows"]["prores-4444"]["visual_parity_required"])

    def testPortablePictureAndAlphaDifferencesStillFail(self):
        passed, report = self.compare(portable_visual_failure=True)
        self.assertFalse(passed)
        self.assertIn("linux-windows/prores-4444: Alpha differs", report["failures"])
        self.assertIn("linux-windows/h264: picture differs", report["failures"])

    def testAudioAndInputIdentityRemainHardRequirements(self):
        self.assertFalse(self.compare(audio_failure=True)[0])
        with self.assertRaisesRegex(AssertionError, "different input"):
            self.compare(fixture_mismatch=True)

    def testPortableArchivesContainOnlyExecutableAndAuditedNotices(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            binary = root / "overlay"
            binary.write_bytes(b"test executable")
            binary.chmod(0o755)
            for system in ["Linux", "Windows"]:
                with patch.object(packaging.platform, "system", return_value=system), patch.object(
                    packaging.platform, "machine", return_value="AMD64"), patch.object(
                    packaging.subprocess, "check_output", side_effect=[b"", "a" * 40]), contextlib.redirect_stdout(io.StringIO()):
                    archive = packaging.package("v0.1.0", binary, root / system)
                digest, name = archive.with_suffix(archive.suffix + ".sha256").read_text().split()
                self.assertEqual(name, archive.name)
                self.assertEqual(digest, hashlib.sha256(archive.read_bytes()).hexdigest())
                if system == "Linux":
                    with tarfile.open(archive) as bundle:
                        members = [m for m in bundle.getmembers() if m.isfile()]
                        self.assertEqual(len(members), 7)
                        executable = next(m for m in members if m.name.endswith("/overlay"))
                        # Windows cannot represent POSIX execute bits; Linux CI checks the real mode.
                        if os.name != "nt":
                            self.assertTrue(executable.mode & 0o111)
                        source = json.loads(bundle.extractfile(next(m for m in members if m.name.endswith("/SOURCE.json"))).read())
                else:
                    with zipfile.ZipFile(archive) as bundle:
                        self.assertEqual(len(bundle.namelist()), 7)
                        self.assertTrue(any(n.endswith("/overlay.exe") for n in bundle.namelist()))
                        source = json.loads(bundle.read(next(n for n in bundle.namelist() if n.endswith("/SOURCE.json"))))
                self.assertEqual(source["revision"], "a" * 40)
                self.assertEqual(source["binary_sha256"], hashlib.sha256(binary.read_bytes()).hexdigest())
                with patch.object(packaging.platform, "system", return_value=system), patch.object(
                    packaging.platform, "machine", return_value="AMD64"), patch.object(
                    packaging.subprocess, "check_output", side_effect=[b"", "a" * 40]):
                    with self.assertRaises(FileExistsError):
                        packaging.package("v0.1.0", binary, root / system)
                self.assertEqual(digest, hashlib.sha256(archive.read_bytes()).hexdigest())


if __name__ == "__main__":
    unittest.main()
