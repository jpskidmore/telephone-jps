#!/usr/bin/env python3
"""Verify the bundled source and prebuilt inventories without compiling code.

These hashes detect checkout drift, not upstream authenticity or reproducible
binary provenance. Update them only as part of a reviewed dependency change.
"""
import hashlib
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "ThirdParty Sources"
EXPECTED_SOURCES = {
    "lame-3.100.tar.gz", "libogg-1.3.6.tar.gz", "libopusenc-0.3.tar.gz",
    "libressl-4.3.2.tar.gz", "libressl-4.3.2.tar.gz.asc", "opus-1.6.1.tar.gz",
    "pjproject-2.17.tar.gz",
}


def verify(manifest, base, expected):
    entries = {}
    for line in manifest.read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if not match:
            raise ValueError(f"Malformed manifest entry in {manifest.name}: {line!r}")
        digest, name = match.groups()
        if name in entries or name not in expected:
            raise ValueError(f"Duplicate or unexpected manifest path: {name}")
        entries[name] = digest
    if set(entries) != expected:
        raise ValueError(f"Manifest inventory mismatch: {sorted(expected - entries.keys())}")
    for name, expected_digest in entries.items():
        path = base / name
        if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
            raise ValueError(f"Missing, empty, or symlinked dependency: {name}")
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(block)
        if digest.hexdigest() != expected_digest:
            raise ValueError(f"SHA-256 mismatch: {name}")
        print(f"SHA-256 OK: {name}")


def main():
    source_files = {p.name for p in SOURCES.iterdir() if p.name != "SHA256SUMS.txt"}
    if source_files != EXPECTED_SOURCES:
        raise ValueError("Source archive inventory differs from the six pinned dependencies")
    verify(SOURCES / "SHA256SUMS.txt", SOURCES, EXPECTED_SOURCES)
    archives = {str(p.relative_to(ROOT)) for p in (ROOT / "ThirdParty").glob("*/lib/*.a")}
    if not archives:
        raise ValueError("No bundled static archives found")
    verify(ROOT / "Scripts/vendor-archives.sha256", ROOT, archives)
    # These are the quoted -l flags currently used by the Xcode project. Every
    # linked library must have exactly one bundled archive, including codecs.
    project = (ROOT / "Telephone.xcodeproj/project.pbxproj").read_text()
    libraries = set(re.findall(r'"-l([A-Za-z0-9_.+-]+)"', project))
    if not libraries:
        raise ValueError("No linked-library flags found; project parser needs review")
    for name in sorted(libraries):
        matches = [path for path in archives if Path(path).name == f"lib{name}.a"]
        if len(matches) != 1:
            raise ValueError(f"Linked library {name} does not resolve to one pinned archive")
    print(f"Dependency manifests passed: {len(EXPECTED_SOURCES)} source files, "
          f"{len(archives)} static archives, {len(libraries)} linked libraries")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"Dependency verification failed: {error}", file=sys.stderr)
        sys.exit(1)
