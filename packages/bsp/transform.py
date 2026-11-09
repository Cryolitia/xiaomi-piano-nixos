"""Adapt the pinned Piano BSP to Nix store paths without running device code."""

import argparse
import importlib.util
from pathlib import Path
import shutil
import sys


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ScriptInstaller:
    """Apply the same path substitutions to every installed runtime script."""

    def __init__(self, args):
        self.output = Path(args.output)
        self.libexec = self.output / "libexec/piano"
        self.share = self.output / "share/piano"
        self.libexec.mkdir(parents=True, exist_ok=True)
        self.share.mkdir(parents=True, exist_ok=True)

        self.interpreters = {
            "#!/usr/bin/python3": "#!" + args.python,
            "#!/usr/bin/env python3": "#!" + args.python,
            "#!/bin/sh": "#!" + args.shell,
        }
        self.replacements = (
            ("/usr/lib/piano", str(self.libexec)),
            ("/usr/share/piano", str(self.share)),
            ("/usr/bin/piano-touch-view", str(self.output / "bin/piano-touch-view")),
        )

    def write(self, name, text):
        interpreter, newline, body = text.partition("\n")
        if interpreter not in self.interpreters:
            raise ValueError(f"{name}: unsupported script interpreter {interpreter!r}")
        text = self.interpreters[interpreter] + newline + body

        for original, replacement in self.replacements:
            text = text.replace(original, replacement)

        target = self.libexec / name
        target.write_text(text)
        target.chmod(0o755)


def install_runtime_scripts(source, installer):
    installer.write(
        "touch-input", (source / "linux/userspace/pen/piano-touch-input").read_text()
    )
    installer.write(
        "pen-bluetooth",
        (source / "linux/userspace/pen/piano-pen-bluetooth.py").read_text(),
    )
    installer.write(
        "usb-network",
        (source / "linux/bsp/common/usr/lib/piano/usb-network").read_text(),
    )


def install_shared_resources(source, installer):
    shutil.copytree(
        source / "linux/bsp/common/usr/share/piano/pen",
        installer.share / "pen",
        dirs_exist_ok=True,
    )
    shutil.copytree(
        source / "linux/bsp/common/usr/share/alsa",
        installer.output / "share/alsa",
        dirs_exist_ok=True,
    )


def prepare_source(source, debian, macros):
    # Load the touch reader source builder from the pinned board source,
    # never from the developer's ambient Python package path.
    sys.path.insert(0, str(source / "tools"))
    helpers = load_module(
        "piano_helpers", source / "tools/build_piano_runtime_helpers.py"
    )
    # Build the reviewed reader with the calibrated pen core in the Nix build;
    # do not install a host executable or a foreign prebuilt tool.
    work = Path.cwd()
    derived, _ = helpers.derive_touch_source(debian, work)
    shutil.copyfile(derived, work / "piano-touch-view.c")
    helpers.build_topology(debian, macros, work / "firmware")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare = commands.add_parser(
        "prepare", help="derive touch source and build audio topology"
    )
    prepare.add_argument("sunuefi", type=Path)
    prepare.add_argument("debian", type=Path)
    prepare.add_argument("macros", type=Path)
    install = commands.add_parser("install", help="install runtime scripts and data")

    for name in ("sunuefi", "output", "shell", "python"):
        install.add_argument("--" + name, required=True)

    args = parser.parse_args()

    if args.command == "prepare":
        prepare_source(args.sunuefi, args.debian, args.macros)
    else:
        installer = ScriptInstaller(args)
        source = Path(args.sunuefi)
        install_runtime_scripts(source, installer)
        install_shared_resources(source, installer)


if __name__ == "__main__":
    main()
