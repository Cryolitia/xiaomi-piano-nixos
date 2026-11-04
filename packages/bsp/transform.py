"""Adapt pinned Linux BSP sources to Nix store paths; never run device code."""
import argparse
import importlib.util
from pathlib import Path
import shutil
import sys


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("sunuefi", "debian", "output", "shell", "python", "blkid", "modprobe"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    sun, debian, out = map(Path, (args.sunuefi, args.debian, args.output))
    sys.path.insert(0, str(sun / "tools"))
    adapters = module("piano_adapters", sun / "tools/stage_piano_ram_hardware.py")
    helpers = module("piano_helpers", sun / "tools/build_piano_runtime_helpers.py")
    libexec = out / "libexec/piano"
    share = out / "share/piano"
    libexec.mkdir(parents=True, exist_ok=True)
    share.mkdir(parents=True, exist_ok=True)

    def write(name, text):
        text = text.replace("#!/usr/bin/python3", "#!" + args.python)
        text = text.replace("#!/usr/bin/env python3", "#!" + args.python)
        text = text.replace("#!/bin/sh", "#!" + args.shell)
        text = text.replace("/usr/bin/python3", args.python)
        text = text.replace("/usr/sbin/blkid", args.blkid)
        text = text.replace("/usr/sbin/modprobe", args.modprobe)
        text = text.replace("/usr/lib/piano/piano-ram-hardware-prepare",
                            str(libexec / "piano-hardware-prepare"))
        text = text.replace("/usr/lib/piano", str(libexec))
        text = text.replace("/usr/share/piano", str(share))
        text = text.replace("/usr/bin/piano-touch-view", str(out / "bin/piano-touch-view"))
        path = libexec / name
        path.write_text(text)
        path.chmod(0o755)

    for name in ("display-start", "touch-start", "radio-start", "adsp-start", "audio-start", "keyboard-start"):
        original = debian / "rootfs/overlay/usr/lib/piano" / name
        write(name, adapters.adapt(name, original.read_bytes()).decode())
    write("cpufreq-start", (debian / "rootfs/overlay/usr/lib/piano/cpufreq-start").read_text())
    write("touch-input", (sun / "linux/userspace/pen/piano-touch-input").read_text())
    write("pen-bluetooth", (sun / "linux/userspace/pen/piano-pen-bluetooth.py").read_text())
    write("bluetooth-address.py", (sun / "linux/bsp/common/usr/lib/piano/bluetooth-address.py").read_text())
    for source, name in (("check_piano_kernel_dma_routes.py", "piano_dma_routes.py"),
                         ("check_piano_kernel_contexts.py", "piano_dma_contexts.py")):
        # Keep the reviewed verifier bytes and their in-driver hash checks.
        shutil.copyfile(sun / "tools" / source, libexec / name)

    guard = (sun / "linux/userspace/piano-ram-hardware-prepare").read_text()
    start = guard.index("def require_ram(")
    end = guard.index("\ndef require_clock(", start)
    guard = guard[:start] + '''def require_ram(proc=Path('/proc'), run=Path('/run')):
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

''' + guard[end:]
    guard = guard.replace("require_ram", "require_board")
    guard = guard.replace("--check-root", "--check-board").replace("args.check_root", "args.check_board")
    guard = guard.replace("Verify only the actual RAM or configured Linux root",
                          "Verify the actual piano board and running kernel modules")
    write("piano-hardware-prepare", guard)
    shutil.copytree(sun / "linux/bsp/common/usr/share/piano/pen", share / "pen", dirs_exist_ok=True)
    shutil.copytree(sun / "linux/bsp/common/usr/share/alsa", out / "share/alsa", dirs_exist_ok=True)
    conf = out / "etc/modprobe.d"
    conf.mkdir(parents=True, exist_ok=True)
    text = (sun / "linux/bsp/common/etc/modprobe.d/piano.conf").read_text()
    text = text.replace("/bin/false", "false")
    (conf / "piano.conf").write_text(text)
    rules = out / "lib/udev/rules.d"
    rules.mkdir(parents=True, exist_ok=True)
    # Leave hardware aliases in sysfs intact for explicit modprobe. Clear
    # only event autoloading for inherited SoC buses, before 80-drivers.rules.
    (rules / "00-piano-module-order.rules").write_text(
        'ACTION=="add", ENV{MODALIAS}=="of:*|platform:*|amba:*|spmi:*|auxiliary:*|slim:*|rpmsg:*|qcom-*", ENV{MODALIAS}=""\n'
    )

    # The same patched reader and calibrated pen core are compiled below;
    # no opaque host executable or foreign prebuilt tool is installed.
    derived, _ = helpers.derive_touch_source(debian, Path.cwd())
    shutil.copyfile(derived, Path.cwd() / "piano-touch-view.c")


if __name__ == "__main__":
    main()
