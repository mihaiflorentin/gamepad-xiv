#!/usr/bin/env python3
"""Writes Changelog.lua, the released versions of CHANGELOG.md, for the in-game changelog (News.lua).

Run from the addon folder: python3 tools/make_changelog.py
The release workflow runs it before packaging, so a release always carries its own changelog.
The Unreleased section is left out.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def plain(text):
    # Markdown marks the game can't show.
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"`(.+?)`", r"\1", text)
    return text.strip()


def main():
    source = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    versions = []
    current = None
    for line in source.splitlines():
        heading = re.match(r"^## (v[\w.\-]+)\s*$", line)
        if heading:
            current = {"version": heading.group(1), "lines": []}
            versions.append(current)
            continue
        if line.startswith("## "):
            current = None  # Unreleased, or anything that isn't a version
            continue
        if current is None:
            continue
        section = re.match(r"^### (.+)$", line)
        bullet = re.match(r"^(\s*)- (.+)$", line)
        if section:
            current["lines"].append(("h", plain(section.group(1))))
        elif bullet:
            current["lines"].append(("-" if not bullet.group(1) else "--", plain(bullet.group(2))))

    out = [
        "local _, ns = ...",
        "",
        "-- Generated from CHANGELOG.md by tools/make_changelog.py. Do not edit; run the script instead.",
        "-- Newest first. Each line is { kind, text }: \"h\" a section, \"-\" an entry, \"--\" a sub-entry.",
        "ns.CHANGELOG = {",
    ]
    for version in versions:
        out.append("\t{ version = %s, lines = {" % lua_string(version["version"]))
        for kind, text in version["lines"]:
            out.append("\t\t{ %s, %s }," % (lua_string(kind), lua_string(text)))
        out.append("\t} },")
    out.append("}")
    (ROOT / "Changelog.lua").write_text("\n".join(out) + "\n", encoding="utf-8")
    print("Changelog.lua: %d versions" % len(versions), file=sys.stderr)


if __name__ == "__main__":
    main()
