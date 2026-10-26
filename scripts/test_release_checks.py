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
import xml.etree.ElementTree as ET
from unittest.mock import patch

import compare_export_fixture as comparison
import package_portable_release as packaging
import collect_portable_runtime as runtime


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

    def testPortableArchivesContainRuntimeNoticesSourcesAndOriginalExecutable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            binary = root / "overlay"
            binary.write_bytes(b"test executable")
            binary.chmod(0o755)
            for system in ["Linux", "Windows"]:
                collected = root / (system + "-runtime")
                (collected / "bin").mkdir(parents=True)
                (collected / "licenses").mkdir()
                (collected / "licenses/FFmpeg").write_text("GPL source remains available")
                shutil_binary = collected / "bin" / ("overlay.exe" if system == "Windows" else "overlay")
                shutil_binary.write_bytes(binary.read_bytes())
                if system == "Windows":
                    shutil_binary.write_bytes(binary.read_bytes() + b"manifest")
                (collected / ("launcher.exe" if system == "Windows" else "launcher")).write_bytes(b"launcher")
                sources = root / (system + "-sources")
                sources.mkdir()
                (sources / "ffmpeg.src.tar").write_bytes(b"matching source")
                (collected / "DEPENDENCIES.json").write_text(json.dumps({"platform": system,
                    "build_binary_sha256": runtime.digest(binary),
                    "files": [{"path": shutil_binary.relative_to(collected).as_posix(), "sha256": runtime.digest(shutil_binary)}],
                    "sources": [{"file": "ffmpeg.src.tar", "sha256": runtime.digest(sources / "ffmpeg.src.tar")}]}))
                with patch.object(packaging.platform, "system", return_value=system), patch.object(
                    packaging.platform, "machine", return_value="AMD64"), patch.object(
                    packaging.subprocess, "check_output", side_effect=[b"", "a" * 40]), contextlib.redirect_stdout(io.StringIO()):
                    archive = packaging.package("v0.1.1", binary, root / system, collected, sources)
                digest, name = archive.with_suffix(archive.suffix + ".sha256").read_text().split()
                self.assertEqual(name, archive.name)
                self.assertEqual(digest, hashlib.sha256(archive.read_bytes()).hexdigest())
                if system == "Linux":
                    with tarfile.open(archive) as bundle:
                        members = [m for m in bundle.getmembers() if m.isfile()]
                        self.assertTrue(any(m.name.endswith("runtime/licenses/FFmpeg") for m in members))
                        self.assertTrue(any(m.name.endswith("/docs/INSTALL.zh-CN.md") for m in members))
                        executable = next(m for m in members if m.name.endswith("/runtime/bin/overlay"))
                        self.assertEqual(bundle.extractfile(executable).read(), shutil_binary.read_bytes())
                        source = json.loads(bundle.extractfile(next(m for m in members if m.name.endswith("/SOURCE.json"))).read())
                else:
                    with zipfile.ZipFile(archive) as bundle:
                        self.assertTrue(any(n.endswith("/runtime/bin/overlay.exe") for n in bundle.namelist()))
                        self.assertEqual(bundle.read(next(n for n in bundle.namelist() if n.endswith("/runtime/bin/overlay.exe"))), shutil_binary.read_bytes())
                        source = json.loads(bundle.read(next(n for n in bundle.namelist() if n.endswith("/SOURCE.json"))))
                self.assertEqual(source["revision"], "a" * 40)
                self.assertEqual(source["binary_sha256"], runtime.digest(shutil_binary))
                self.assertEqual(source["build_binary_sha256"], runtime.digest(binary))
                with tarfile.open(archive.parent / source["dependency_sources"]) as bundle:
                    self.assertEqual(bundle.extractfile("dependency-sources/ffmpeg.src.tar").read(), b"matching source")
                with patch.object(packaging.platform, "system", return_value=system), patch.object(
                    packaging.platform, "machine", return_value="AMD64"), patch.object(
                    packaging.subprocess, "check_output", side_effect=[b"", "a" * 40]):
                    with self.assertRaises(FileExistsError):
                        packaging.package("v0.1.1", binary, root / system, collected, sources)
                self.assertEqual(digest, hashlib.sha256(archive.read_bytes()).hexdigest())
                (sources / "ffmpeg.src.tar").write_bytes(b"wrong source")
                with patch.object(packaging.platform, "system", return_value=system), patch.object(
                    packaging.platform, "machine", return_value="AMD64"):
                    with self.assertRaisesRegex(ValueError, "checksum"):
                        packaging.package("v0.1.2", binary, root / system, collected, sources)

    def testMissingDependenciesFailRatherThanUsingIncompleteRelease(self):
        failure=runtime.subprocess.CalledProcessError(1,['dpkg-query'],stderr='no package owner')
        with patch.object(runtime.subprocess,'check_output',side_effect=failure):
            with self.assertRaises(runtime.subprocess.CalledProcessError):
                runtime.run('dpkg-query','-S','/lib/alias.so')
        with patch.object(runtime, "run", return_value="libswiftCore.so => not found"):
            with self.assertRaisesRegex(ValueError, "Unresolved"):
                runtime.linux_dependencies("overlay")
        with patch.object(runtime, "run", return_value="libc.so.6 => /lib/libc.so.6 (0x1)\nlibcairo.so.2 => /lib/libcairo.so.2 (0x2)"):
            self.assertEqual(runtime.linux_dependencies("overlay"), [pathlib.Path("/lib/libcairo.so.2")])

    def testWindowsUnicodeManifestPreservesExistingExecutionPolicy(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tool = root / "Windows Kits/10/bin/10.0/x64/mt.exe"
            tool.parent.mkdir(parents=True)
            tool.touch()
            calls = []
            def manifest_command(command, **kwargs):
                calls.append(command)
                if any(a.startswith('-out:') for a in command):
                    path = pathlib.Path(next(a[5:] for a in command if a.startswith('-out:')))
                    path.write_text('<assembly xmlns="urn:schemas-microsoft-com:asm.v1"><trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="asInvoker"/></requestedPrivileges></security></trustInfo></assembly>')
                else:
                    document = ET.parse(command[command.index('-manifest')+1])
                    ns={'a':'urn:schemas-microsoft-com:asm.v3','w':'http://schemas.microsoft.com/SMI/2019/WindowsSettings'}
                    self.assertEqual(document.find('.//a:requestedExecutionLevel',ns).get('level'),'asInvoker')
                    self.assertEqual(document.find('.//w:activeCodePage',ns).text,'UTF-8')
                return runtime.subprocess.CompletedProcess(command,0,stdout='')
            with patch.dict(os.environ, {'ProgramFiles(x86)':str(root)}), patch.object(runtime.subprocess,'run',side_effect=manifest_command):
                runtime.windows_utf8_manifest(root/'overlay.exe')
            self.assertEqual(len(calls),2)

    def testWindowsRawExecutableGetsAManifestWithoutNewPrivileges(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory)
            tool=root/'Windows Kits/10/bin/10.0/x64/mt.exe';tool.parent.mkdir(parents=True);tool.touch()
            def manifest_command(command,**kwargs):
                if any(a.startswith('-inputresource:') for a in command):
                    return runtime.subprocess.CompletedProcess(command,31,stdout='The specified image file did not contain a resource section.')
                document=ET.parse(command[command.index('-manifest')+1])
                self.assertIsNone(document.find('.//{urn:schemas-microsoft-com:asm.v3}requestedExecutionLevel'))
                self.assertEqual(document.find('.//{http://schemas.microsoft.com/SMI/2019/WindowsSettings}activeCodePage').text,'UTF-8')
                return runtime.subprocess.CompletedProcess(command,0,stdout='')
            with patch.dict(os.environ,{'ProgramFiles(x86)':str(root)}),patch.object(runtime.subprocess,'run',side_effect=manifest_command):
                runtime.windows_utf8_manifest(root/'overlay.exe')


if __name__ == "__main__":
    unittest.main()
