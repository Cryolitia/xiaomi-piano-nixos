"""Merge the upstream hardware config without its distro-specific init command."""
import re
import sys
from pathlib import Path

kernel, sunuefi = map(Path, sys.argv[1:])
fragments = [
    kernel / "arch/arm64/configs/piano_defconfig",
    kernel / "arch/arm64/configs/piano_rootfs.config",
]
fragments += [sunuefi / "linux/configs" / name for name in (
    "piano-bluetooth.config",
    "piano-flash.config",
    "piano-pen-dock.config",
    "piano-cpucp-early.config",
    "piano-userspace-security.config",
    "piano-sleep.config",
    "piano-platform.config",
)]
settings = {}
for fragment in fragments:
    for line in fragment.read_text().splitlines():
        enabled = re.fullmatch(r"(CONFIG_[A-Z0-9_]+)=(.*)", line)
        disabled = re.fullmatch(r"# (CONFIG_[A-Z0-9_]+) is not set", line)
        if enabled:
            settings[enabled[1]] = line
        elif disabled:
            settings[disabled[1]] = line
# Boot arguments belong to the importing NixOS configuration, never Android's
# userdata or the old /beaconinit and /pianoinit bootstraps.
settings.update({
    "CONFIG_CMDLINE": 'CONFIG_CMDLINE=""',
    "CONFIG_CMDLINE_FORCE": "# CONFIG_CMDLINE_FORCE is not set",
    "CONFIG_LOCALVERSION": 'CONFIG_LOCALVERSION="-piano-nixos"',
    "CONFIG_LOCALVERSION_AUTO": "# CONFIG_LOCALVERSION_AUTO is not set",
})
(kernel / "arch/arm64/configs/piano_nixos_defconfig").write_text(
    "\n".join(settings[name] for name in sorted(settings)) + "\n"
)
