{
  config,
  lib,
  pkgs,
  pianoPackages,
  ...
}:

let
  pen = config.hardware.xiaomi.piano.pen;
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

  # The touch driver exposes its THP stream before the bind event. Keep the
  # device inactive until then so systemd starts the reader with a real stream.
  services.udev.extraRules = ''
    SUBSYSTEM=="spi", ATTR{modalias}=="spi:NVT-ts-spi", TAG+="systemd", ENV{SYSTEMD_READY}="0"
    SUBSYSTEM=="spi", DRIVER=="NVT-ts-spi", TEST=="/proc/nvt_thp_stream", ENV{SYSTEMD_READY}="1", ENV{SYSTEMD_WANTS}+="piano-touch.service"
  '';

  systemd.services = {
    piano-touch = {
      description = "Piano THP touch input";
      preStart = lib.optionalString (!pen.enable) ''
        # A previous pen-enabled reader may have left stylus scanning active.
        echo 0 > /proc/nvt_thp_stylus
      '';
      serviceConfig = {
        Type = "simple";
        ExecStart =
          if pen.enable then
            "${runtime}/touch-input"
          else
            "${pianoPackages.bsp}/bin/piano-touch-view input --seconds 0";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    bluetooth = lib.mkIf config.hardware.bluetooth.enable {
      # The kernel owns power and firmware loading. Only missing per-device
      # identity still needs MGMT provisioning before BlueZ takes over.
      serviceConfig.ExecStartPre = "-+${runtime}/bluetooth-address.py";
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
