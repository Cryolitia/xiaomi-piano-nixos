{ lib, pkgs, ... }:

let
  saveFirmwareDump = pkgs.writeShellScript "save-piano-firmware-dump" ''
    set -eu

    # Read an existing kernel snapshot. This does not request a firmware crash
    # or release the snapshot through its writable sysfs control interface.
    source="/sys/class/devcoredump/$1/data"
    boot_id=$(cat /proc/sys/kernel/random/boot_id)
    partial=$(mktemp "$STATE_DIRECTORY/$boot_id-$1.XXXXXX.partial")

    cp "$source" "$partial"
    sync -f "$partial"
    destination="''${partial%.partial}.dump"
    mv "$partial" "$destination"
    sync -f "$STATE_DIRECTORY"

    echo "Firmware crash snapshot saved to $destination"
  '';
in
{
  imports = [ ./usb-debug.nix ];

  # These settings belong to the validation image. Hardware-only consumers
  # keep their own logging policy and do not acquire USB diagnostic services.
  boot.kernelPatches = [
    {
      name = "piano-wifi-diagnostics";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        ATH12K_DEBUG = yes;
        ATH12K_DEBUGFS = yes;
        ATH12K_TRACING = yes;
        ATH12K_COREDUMP = yes;
        MAC80211_DEBUGFS = yes;
      };
    }
  ];

  boot.consoleLogLevel = 8;
  boot.kernelParams = [ "log_buf_len=4M" ];
  boot.extraModprobeConfig = lib.mkAfter ''
    # PCI, QMI, firmware boot, MAC and WMI; leave per-packet dumps disabled.
    options ath12k debug_mask=0x1072
  '';

  # Report blocked tasks while the USB output path can still make progress.
  # Keep the existing panic policy so a diagnostic warning does not reboot.
  boot.kernel.sysctl = {
    "kernel.hung_task_timeout_secs" = 30;
    "kernel.sysrq" = 1;
  };

  services.journald.settings.Journal = {
    Storage = "persistent";
    SyncIntervalSec = "1s";
    MaxLevelStore = "debug";
    RateLimitIntervalSec = 0;
    SystemMaxUse = "256M";
  };

  # A firmware dump expires in sysfs. Archive it on the Linux filesystem so
  # it can be retrieved over USB even after the driver's recovery completes.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="devcoredump", TAG+="systemd", ENV{SYSTEMD_WANTS}+="piano-firmware-dump@%k.service"
  '';

  systemd.services."piano-firmware-dump@" = {
    description = "Archive firmware crash snapshot %i";
    unitConfig.ConditionPathExists = "/sys/class/devcoredump/%i/data";
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${saveFirmwareDump} %i";
      StateDirectory = "piano-diagnostics/firmware";
      StateDirectoryMode = "0700";
      UMask = "0077";
      TimeoutStartSec = 120;
      ProtectSystem = "strict";
      ProtectKernelTunables = true;
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
}
