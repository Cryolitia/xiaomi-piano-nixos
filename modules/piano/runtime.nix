{
  config,
  lib,
  pkgs,
  pianoPackages,
  ...
}:

let
  runtime = "${pianoPackages.bsp}/libexec/piano";
  unit =
    {
      description,
      start,
      after,
      timeout,
    }:
    {
      inherit description after;
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = timeout;
        ExecStart = start;
      };
    };
in
{
  # This kernel source exposes MiPPS transport but has no in-kernel auth.
  # Use the existing ordinary PD buck path, preserving its thermal limits.
  environment.etc."piano/adsp.conf".text = ''
    CHARGE_MIPPS=0
    CHARGE_CP=0
  '';

  # The onboard firmware may report an empty MAC and the driver then chooses
  # a random one. A per-profile stable address survives boots and takes effect
  # before association; an explicit address in a saved profile still wins.
  networking.networkmanager.settings = lib.mkIf config.networking.networkmanager.enable {
    connection-piano-wlan = {
      match-device = "driver:ath12k_wifi7_pci";
      "wifi.cloned-mac-address" = "stable";
    };
  };

  # CPUCP and SCMI cpufreq are built in: policies exist before userspace.
  # The normal tmpfiles reactivation also applies this during nixos-rebuild.
  systemd.tmpfiles.rules = [
    "w /sys/devices/system/cpu/cpufreq/boost - - - - 1"
  ];

  systemd.services = {
    piano-display =
      (unit {
        description = "Piano native display and GPU";
        # Clock suppliers and panel/backlight register before their consumer.
        # The kernel can then finish probing without manual drivers_probe writes.
        start = [
          "${pkgs.kmod}/bin/modprobe --all dispcc_sm8750 gpi i2c_qcom_geni ktz8866 panel_novatek_nt36532"
          "${pkgs.kmod}/bin/modprobe msm separate_gpu_kms=1"
        ];
        after = [ "systemd-udev-trigger.service" ];
        timeout = 240;
      })
      // {
        before = [ "display-manager.service" ];
        # A DRM node can exist while DSI is still enabling. ADSP must wait for
        # the native panel to take over the bootloader's shared display rails.
        postStart = ''
          remaining=150
          until ${pkgs.gnugrep}/bin/grep -qx enabled /sys/class/drm/card*-DSI-1/enabled 2>/dev/null; do
            if [ "$remaining" -eq 0 ]; then
              echo "Piano display: DSI output did not enable within 150 seconds" >&2
              exit 1
            fi

            sleep 1
            remaining=$((remaining - 1))
          done
          test -e /sys/bus/platform/drivers/adreno/3d00000.gpu
        '';
      };

    display-manager = lib.mkIf config.services.displayManager.enable {
      requires = [ "piano-display.service" ];
      after = [ "piano-display.service" ];
    };

    piano-touch = {
      description = "Piano THP touch and pen input";
      wantedBy = [ "multi-user.target" ];
      wants = [ "piano-display.service" ];
      after = [
        "systemd-udev-trigger.service"
        "piano-display.service"
      ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${runtime}/touch-start";
        ExecStart = "${runtime}/touch-input";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 60;
      };
    };

    piano-radio =
      (unit {
        description = "Piano WLAN and Bluetooth";
        start = "${runtime}/radio-start";
        after = [
          "systemd-udev-trigger.service"
          "piano-touch.service"
        ];
        timeout = 180;
      })
      // {
        wants = [ "piano-touch.service" ];
        before = [ "bluetooth.service" ];
      };

    bluetooth = lib.mkIf config.hardware.bluetooth.enable {
      wants = [ "piano-radio.service" ];
      after = [ "piano-radio.service" ];
    };

    piano-adsp =
      (unit {
        description = "Piano ADSP and charging";
        start = "${runtime}/adsp-start";
        after = [
          "systemd-udev-trigger.service"
          "piano-display.service"
          "piano-touch.service"
        ];
        timeout = 120;
      })
      // {
        requires = [ "piano-display.service" ];
      };

    piano-audio =
      (unit {
        description = "Piano sound card";
        # ASoC and the GPR bus defer probing until their components appear.
        # Register the DSP drivers, check its DMA route, then expose the card.
        start = [
          "${pkgs.kmod}/bin/modprobe --all snd_soc_fs19xx apr snd_q6apm q6prm q6prm_clocks q6apm_lpass_dais q6apm_dai"
          "${runtime}/piano-hardware-prepare --require-scope audio --wait-seconds 20"
          "${pkgs.kmod}/bin/modprobe --all pinctrl_sm8650_lpass_lpi snd_soc_lpass_va_macro snd_soc_sc8280xp"
          "${config.systemd.package}/bin/udevadm wait --timeout=30 /dev/snd/controlC0"
        ];
        after = [ "piano-adsp.service" ];
        timeout = 120;
      })
      // {
        requires = [ "piano-adsp.service" ];
      };

    piano-keyboard =
      lib.recursiveUpdate
        (unit {
          description = "Load Piano keyboard cover driver";
          start = "${pkgs.kmod}/bin/modprobe hid_nanosic_wn8030";
          after = [
            "piano-touch.service"
            "piano-display.service"
          ];
          timeout = 60;
        })
        {
          wants = [
            "piano-touch.service"
            "piano-display.service"
          ];
          serviceConfig.ExecStartPre = "${runtime}/piano-hardware-prepare --require-scope keyboard --wait-seconds 20";
        };
  };
}
