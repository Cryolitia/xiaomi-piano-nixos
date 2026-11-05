"""Adapt the pinned Piano BSP to Nix store paths without running device code."""

import argparse
import importlib.util
from pathlib import Path
import shutil
import sys


START_SCRIPTS = (
    "display-start",
    "touch-start",
    "radio-start",
    "adsp-start",
    "audio-start",
    "keyboard-start",
)


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

        # Replace shebangs before generic executable paths, and the specific
        # hardware entry before its containing directory. Order is significant.
        self.interpreters = {
            "#!/usr/bin/python3": "#!" + args.python,
            "#!/usr/bin/env python3": "#!" + args.python,
            "#!/bin/sh": "#!" + args.shell,
        }
        self.replacements = (
            # Execute the installed helper so wrapProgram's shell wrapper runs.
            # Passing that wrapper to Python would parse shell code as Python.
            (
                "/usr/bin/python3 /usr/lib/piano/bluetooth-address.py",
                str(self.libexec / "bluetooth-address.py"),
            ),
            ("/usr/bin/python3", args.python),
            ("/usr/sbin/blkid", args.blkid),
            ("/usr/sbin/modprobe", args.modprobe),
            (
                "/usr/lib/piano/piano-ram-hardware-prepare",
                str(self.libexec / "piano-hardware-prepare"),
            ),
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


def install_runtime_scripts(source, debian, installer, adapters):
    for name in START_SCRIPTS:
        original = debian / "rootfs/overlay/usr/lib/piano" / name
        installer.write(name, adapters.adapt(name, original.read_bytes()).decode())

    installer.write(
        "cpufreq-start",
        (debian / "rootfs/overlay/usr/lib/piano/cpufreq-start").read_text(),
    )
    installer.write(
        "touch-input", (source / "linux/userspace/pen/piano-touch-input").read_text()
    )
    installer.write(
        "pen-bluetooth",
        (source / "linux/userspace/pen/piano-pen-bluetooth.py").read_text(),
    )
    installer.write(
        "bluetooth-address.py",
        (source / "linux/bsp/common/usr/lib/piano/bluetooth-address.py").read_text(),
    )

    installer.write(
        "usb-network",
        (source / "linux/bsp/common/usr/lib/piano/usb-network").read_text(),
    )


def install_hardware_checks(source, installer):
    for original, installed in (
        ("check_piano_kernel_dma_routes.py", "piano_dma_routes.py"),
        ("check_piano_kernel_contexts.py", "piano_dma_contexts.py"),
    ):
        # These verifier bytes are also checked by the driver-side hash logic.
        # Copy them unchanged rather than applying runtime path substitutions.
        shutil.copyfile(source / "tools" / original, installer.libexec / installed)

    guard = (source / "linux/userspace/piano-ram-hardware-prepare").read_text()
    installer.write("piano-hardware-prepare", guard)


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

    configuration = installer.output / "etc/modprobe.d"
    configuration.mkdir(parents=True, exist_ok=True)
    text = (source / "linux/bsp/common/etc/modprobe.d/piano.conf").read_text()
    (configuration / "piano.conf").write_text(text.replace("/bin/false", "false"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)

    for name in ("sunuefi", "debian", "output", "shell", "python", "blkid", "modprobe"):
        parser.add_argument("--" + name, required=True)

    args = parser.parse_args()
    source = Path(args.sunuefi)
    debian = Path(args.debian)

    # Load both transformations from the pinned source used by the kernel and
    # board policy, never from the developer's ambient Python package path.
    sys.path.insert(0, str(source / "tools"))
    adapters = load_module(
        "piano_adapters", source / "tools/stage_piano_ram_hardware.py"
    )
    helpers = load_module(
        "piano_helpers", source / "tools/build_piano_runtime_helpers.py"
    )
    installer = ScriptInstaller(args)

    install_runtime_scripts(source, debian, installer, adapters)
    install_hardware_checks(source, installer)
    install_shared_resources(source, installer)

    # Build the reviewed reader with the calibrated pen core in the Nix build;
    # do not install a host executable or a foreign prebuilt tool.
    work = Path.cwd()
    derived, _ = helpers.derive_touch_source(debian, work)
    shutil.copyfile(derived, work / "piano-touch-view.c")


if __name__ == "__main__":
    main()
