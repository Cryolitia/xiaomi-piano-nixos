"""Adapt the pinned Piano BSP to Nix store paths without running device code."""

import argparse
import ast
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

# These are dependencies in the pinned source, not a hardware-state snapshot.
# Optional substitutions remain optional; losing a required call needs review
# when the upstream source pin is updated.
HARDWARE_GUARD = "/usr/lib/piano/piano-ram-hardware-prepare"
REQUIRED_PATHS = {
    "touch-start": {HARDWARE_GUARD: 1},
    "radio-start": {
        HARDWARE_GUARD: 3,
        "/usr/bin/python3 /usr/lib/piano/bluetooth-address.py": 1,
    },
    "adsp-start": {HARDWARE_GUARD: 1},
    "audio-start": {HARDWARE_GUARD: 1},
    "keyboard-start": {HARDWARE_GUARD: 1},
    "touch-input": {"/usr/bin/piano-touch-view": 2, "/usr/share/piano": 4},
    "piano-hardware-prepare": {
        "/usr/sbin/modprobe": 1,
        "/usr/lib/piano": 2,
    },
}

# Replace only the distribution-specific board/root precheck. The pinned
# hardware guard still owns every subsequent live DMA and clock check.
NIXOS_BOARD_CHECK = '''def require_ram(proc=Path('/proc'), run=Path('/run')):
    # NixOS stage 1 owns the root policy. This hardware entry checks the
    # actual board and running module ABI, and leaves all per-master DMA
    # and clock checks below intact. It never authorizes raw register IO.
    compatible = Path('/sys/firmware/devicetree/base/compatible').read_bytes().split(b'\\0')
    if b'xiaomi,piano' not in compatible:
        raise Refused('hardware is not Xiaomi Pad 8 Pro (piano)')
    release = os.uname().release
    tree = Path('/run/booted-system/kernel-modules/lib/modules') / release
    if not tree.is_dir():
        raise Refused('matching booted NixOS kernel modules are missing')

'''


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect_count(text, anchor, expected, context):
    actual = text.count(anchor)
    if actual != expected:
        raise ValueError(
            f"{context}: expected {expected} occurrences of {anchor!r}, found {actual}"
        )


def adapt_hardware_check(guard):
    """Replace only the reviewed board/root check and its existing call sites."""
    nodes = ast.parse(guard).body
    functions = {}
    for name in ("require_ram", "require_clock"):
        found = [
            (index, node)
            for index, node in enumerate(nodes)
            if isinstance(node, ast.FunctionDef) and node.name == name
        ]
        if len(found) != 1 or found[0][1].decorator_list:
            raise ValueError(
                f"hardware check: expected one undecorated {name} function"
            )
        functions[name] = found[0]

    # Do not silently discard a new helper or top-level statement inserted
    # between the root check and the clock check in a later source revision.
    start_index, root_check = functions["require_ram"]
    end_index, clock_check = functions["require_clock"]
    if end_index != start_index + 1:
        raise ValueError(
            "hardware check: require_ram and require_clock must be adjacent"
        )

    lines = guard.splitlines(keepends=True)
    start = sum(map(len, lines[: root_check.lineno - 1]))
    end = sum(map(len, lines[: clock_check.lineno - 1])) - 1
    if not guard[start:].startswith("def require_ram(") or not guard[end:].startswith(
        "\ndef require_clock("
    ):
        raise ValueError("hardware check: function source boundaries changed")
    guard = guard[:start] + NIXOS_BOARD_CHECK + guard[end:]

    for original, replacement, count in (
        ("require_ram", "require_board", 3),
        ("--check-root", "--check-board", 1),
        ("args.check_root", "args.check_board", 1),
        (
            "Verify only the actual RAM or configured Linux root",
            "Verify the actual piano board and running kernel modules",
            1,
        ),
    ):
        expect_count(guard, original, count, "hardware check")
        guard = guard.replace(original, replacement)
    return guard


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
        for path, count in REQUIRED_PATHS.get(name, {}).items():
            expect_count(text, path, count, name)

        interpreter = text.partition("\n")[0]
        if interpreter not in self.interpreters:
            raise ValueError(f"{name}: unsupported script interpreter {interpreter!r}")
        expect_count(text, interpreter, 1, name)
        text = text.replace(interpreter, self.interpreters[interpreter])

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


def install_hardware_checks(source, installer):
    for original, installed in (
        ("check_piano_kernel_dma_routes.py", "piano_dma_routes.py"),
        ("check_piano_kernel_contexts.py", "piano_dma_contexts.py"),
    ):
        # These verifier bytes are also checked by the driver-side hash logic.
        # Copy them unchanged rather than applying runtime path substitutions.
        shutil.copyfile(source / "tools" / original, installer.libexec / installed)

    guard = (source / "linux/userspace/piano-ram-hardware-prepare").read_text()
    installer.write("piano-hardware-prepare", adapt_hardware_check(guard))


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
    expect_count(text, "/bin/false", 1, "modprobe configuration")
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
