"""Build the plain-zip artifact for a mod, mirroring `modkit pack`.

Vendored into this repo so a release can be built from the tagged tree alone.
`.github/workflows/release.yml` is the caller: it checks the repo out into a
directory named after the mod id, because the wrapper folder below is taken
from the directory name.  Keep this in step with the copy it came from.

The `.modpkg` comes from the engine's own tool (`tools/modkit.py pack`); this
script produces the same payload as a plain zip, for an install that does not
use the mod manager.  The two must agree, so the rules are modkit's own:

  * `.modkitignore` entries are EXACT relative paths, matched against
    `os.path.relpath(full, mod_root)` -- never a prefix, never a glob.  A
    root-prefixed comparison (or a `startswith`) silently ships dev files.
  * dotted files and dotted directories are skipped at every level, which is
    what keeps `.gitignore`, `.modkitignore` and `.git/` out.
  * entries are stored under `<mod-id>/...` and stamped with a fixed date, so
    two runs of the same tree produce byte-identical archives.

Usage:  python build_release.py <mod-dir> [-o out.zip]
"""

import argparse
import os
import sys
import zipfile

SKIP_DIRS = {".git"}


def ignored_paths(mod_root):
    """The exact relative paths listed in .modkitignore."""
    ignored = set()
    path = os.path.join(mod_root, ".modkitignore")
    if not os.path.isfile(path):
        return ignored
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line and not line.startswith("#"):
                ignored.add(line.replace("\\", "/"))
    return ignored


def payload(mod_root, ignored):
    """(relative path, absolute path) for every file the package carries."""
    files = []
    for base, dirs, names in os.walk(mod_root):
        dirs[:] = sorted(d for d in dirs
                         if not d.startswith(".") and d not in SKIP_DIRS)
        for name in sorted(names):
            if name.startswith("."):
                continue
            full = os.path.join(base, name)
            rel = os.path.relpath(full, mod_root).replace(os.sep, "/")
            if rel in ignored:
                continue
            files.append((rel, full))
    return sorted(files)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mod")
    parser.add_argument("-o", "--output")
    args = parser.parse_args(argv)

    mod_root = os.path.abspath(args.mod)
    mod_id = os.path.basename(mod_root)
    out = args.output or f"{mod_id}.zip"

    ignored = ignored_paths(mod_root)
    files = payload(mod_root, ignored)
    if not files:
        print("nothing to package", file=sys.stderr)
        return 1

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for rel, full in files:
            info = zipfile.ZipInfo(f"{mod_id}/{rel}",
                                   date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(full, "rb") as handle:
                archive.writestr(info, handle.read())
    print(f"wrote {out} ({len(files)} files)")
    for rel, _ in files:
        print(f"  {rel}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
