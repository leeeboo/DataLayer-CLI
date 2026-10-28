#!/usr/bin/env python3
"""Check the actual executable's exit codes and stdout/stderr contract."""
import pathlib
import subprocess
import sys


binary = str(pathlib.Path(sys.argv[1]).resolve())
for argument, expected_status in [("--bogus", 2), ("--help", 0)]:
    result = subprocess.run([binary, argument], capture_output=True, timeout=15)
    assert result.returncode == expected_status, (argument, result.returncode)
    if expected_status:
        assert not result.stdout, "Argument errors must leave stdout empty"
        assert result.stderr, "Argument errors must explain the failure on stderr"
    else:
        assert result.stdout, "Help must be printed on stdout"
        assert not result.stderr, "Help must leave stderr empty"
print("CLI error/help output streams and exit codes passed.")
