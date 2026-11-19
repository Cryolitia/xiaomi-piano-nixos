{
  config,
  lib,
  pkgs,
  pianoPackages,
  pianoSunuefiSrc,
  ...
}:

let
  penBluetooth = config.hardware.xiaomi.piano.pen.enable && config.hardware.bluetooth.enable;
  bspRules = pianoSunuefiSrc + "/linux/bsp/common/etc/udev/rules.d";
  runtime = "${pianoPackages.bsp}/libexec/piano";
in
{
  # The firmware may report an empty MAC. NetworkManager supplies a stable
  # address before association; an explicit saved connection address wins.
  networking.networkmanager.settings = lib.mkIf config.networking.networkmanager.enable {
    connection-piano-wlan = {
      match-device = "driver:ath12k_wifi7_pci";
      "wifi.cloned-mac-address" = "stable";
    };
  };

  services.udev.extraRules =
    builtins.readFile (bspRules + "/79-piano-pen-touch-group.rules")
    + lib.optionalString penBluetooth (builtins.readFile (bspRules + "/79-piano-touch.rules"));

  nixpkgs.overlays = [
    (final: previous: {
      libwacom = import ../../packages/sunuefi-patches.nix {
        inherit lib;
        sunuefiSrc = pianoSunuefiSrc;
        package = previous.libwacom;
        component = "libwacom";
        seriesVersion = lib.versions.majorMinor previous.libwacom.version;
      };
    })
  ];

  systemd.services = {
    piano-touch = lib.mkIf penBluetooth {
      description = "Initialize the Piano pen over Bluetooth";
      after = [
        "systemd-udev-trigger.service"
        "bluetooth.service"
      ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${runtime}/pen-control --follow";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 60;
      };
    };

    piano-adsp = {
      description = "Start Piano ADSP after display handover";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-udev-trigger.service" ];
      path = [
        pkgs.coreutils
        pkgs.gnugrep
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 180;
      };
      script = ''
        # All drivers load through their normal aliases. Remoteproc remains
        # opt-in because this firmware touches the bootloader's display rails.
        remoteproc=
        remaining=20
        while [ -z "$remoteproc" ]; do
          for candidate in /sys/class/remoteproc/remoteproc*; do
            if [ -r "$candidate/name" ] && [ "$(cat "$candidate/name")" = adsp ]; then
              remoteproc=$candidate
              break
            fi
          done
          if [ -z "$remoteproc" ]; then
            if [ "$remaining" -eq 0 ]; then
              echo "Piano ADSP: remoteproc device did not appear" >&2
              exit 1
            fi
            sleep 1
            remaining=$((remaining - 1))
          fi
        done

        # Rebuilds may restart this unit with a blanked panel and running DSP.
        if [ "$(cat "$remoteproc/state")" = running ]; then
          exit 0
        fi

        # A DRM node alone does not mean the panel has taken over its rails.
        remaining=150
        until grep -qx enabled /sys/class/drm/card*-DSI-1/enabled 2>/dev/null; do
          if [ "$remaining" -eq 0 ]; then
            echo "Piano ADSP: display handover did not complete" >&2
            exit 1
          fi
          sleep 1
          remaining=$((remaining - 1))
        done

        if [ "$(cat "$remoteproc/state")" != running ]; then
          echo start > "$remoteproc/state"
        fi
        test "$(cat "$remoteproc/state")" = running
      '';
    };
  };
}
