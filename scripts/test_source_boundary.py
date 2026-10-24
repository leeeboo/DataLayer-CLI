import pathlib
import json
import os
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from check_source_boundary import checked_file, validate_sources, ROOT


class SourceBoundaryTests(unittest.TestCase):
    @patch.dict(os.environ, {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}, clear=True)
    def test_staged_ui_import_is_rejected_even_after_worktree_is_fixed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            source = root / "Sources/OverlayCore/Example.swift"
            source.parent.mkdir(parents=True)
            source.write_text("import SwiftUI\n")
            (root / "audit").mkdir()
            (root / "audit/files.json").write_text(json.dumps(["Sources/OverlayCore/Example.swift"]))
            subprocess.run(["git", "-C", str(root), "add", "Sources", "audit"], check=True)
            source.write_text("import Foundation\n")
            validate_sources(root)
            with self.assertRaises(ValueError):
                validate_sources(root, staged=True)

    def test_repository_stays_within_audited_boundary(self):
        validate_sources(ROOT)

    def test_escaped_sources_credentials_and_ui_imports_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / "link").symlink_to("/etc/hosts")
            for path in ("../outside", "/etc/hosts", "link"):
                with self.assertRaises(ValueError):
                    checked_file(root, path)
            (root / "credential.txt").write_text("-----BEGIN " + "PRIVATE KEY-----")
            with self.assertRaises(ValueError):
                checked_file(root, "credential.txt")
            source = root / "Sources/OverlayCore/Example.swift"
            source.parent.mkdir(parents=True)
            for module in ("SwiftUI", "AppKit", "UIKit"):
                source.write_text("@preconcurrency import " + module)
                with self.assertRaises(ValueError):
                    checked_file(root, str(source.relative_to(root)))
            source.write_text("// import AppKit\nimport Foundation\n")
            self.assertIn(b"Foundation", checked_file(root, str(source.relative_to(root))))


if __name__ == "__main__":
    unittest.main()
