#!/usr/bin/env python3
"""Run the normal course build, then inject the mobile-first LMS layer."""
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
subprocess.run([sys.executable, str(root / "scripts/build-course.py")], check=True)
out = root / "www" / "index.html"
lms = (root / "course" / "lms-ui.js").read_text(encoding="utf-8")
mobile_css = (root / "course" / "lms-mobile-fix.css").read_text(encoding="utf-8")
src = out.read_text(encoding="utf-8")

old = "connectors:viewConnectors, collocations:viewCollocations, compare:viewCompare"
new = old + ", classroom:(window.viewClassroom||viewHome), students:(window.viewStudents||viewHome), assignments:(window.viewAssignments||viewHome), announcements:(window.viewAnnouncements||viewHome), notifications:(window.viewNotifications||viewHome), audit:(window.viewAudit||viewHome), teachers:(window.viewTeachers||viewHome)"
if old not in src:
    raise SystemExit("Could not locate the course route registry")
src = src.replace(old, new, 1)
marker = "</body>"
if marker not in src:
    raise SystemExit("Could not locate </body>")
injection = "<script>" + lms + "</script><style id=\"spLmsMobileFix\">" + mobile_css + "</style>"
src = src.replace(marker, injection + marker, 1)
out.write_text(src, encoding="utf-8")
print("Injected LMS staff dashboards, notifications, theme, mobile overflow hardening and password-only authentication into www/index.html")
