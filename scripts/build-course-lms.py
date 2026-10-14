#!/usr/bin/env python3
"""Compatibility wrapper: build-course.py now bundles the staff/LMS layer too."""
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
subprocess.run([sys.executable, str(root / "scripts" / "build-course.py")], check=True)
