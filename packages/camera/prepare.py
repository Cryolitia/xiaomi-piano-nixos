"""Prepare the shared camera sources and device-free help entry points."""

import argparse
from pathlib import Path
import shutil
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("debian_source", type=Path)
    args = parser.parse_args()

    work = Path.cwd()
    sys.path.insert(0, str(work / "tools"))
    from build_piano_runtime_helpers import derive_camerad_source, entry_source

    # Keep source verification and the six camera patches in the shared builder.
    derived, _ = derive_camerad_source(args.debian_source, work)
    shutil.copyfile(derived, work / "piano-camerad.c")

    for name in ("piano-camerad", "piano-camera-ctl"):
        (work / (name + "-entry.c")).write_text(entry_source(name))


if __name__ == "__main__":
    main()
