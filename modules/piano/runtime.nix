{
  config,
  lib,
  pianoPackages,
  ...
}:

let
  runtime = "${pianoPackages.bsp}/libexec/piano";
  unit =
    {
      description,
      command,
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
        ExecStartPre = "${runtime}/piano-hardware-prepare --check-board";
        ExecStart = "${runtime}/${command}";
      };
    };
in
{
  # Board bring-up programs retain their reviewed hardware checks and order.
  # Only distribution paths and service dependencies are defined here.
  environment.etc."piano/display.conf".text = ''
    MSM_OPTIONS=separate_gpu_kms=1
    LAST_STAGE=5
  '';

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

  systemd.services = {
    piano-display =
      (unit {
        description = "Piano native display and GPU";
        command = "display-start --all";
        after = [ "systemd-udev-trigger.service" ];
        timeout = 240;
      })
      // {
        before = [ "display-manager.service" ];
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
        ExecStartPre = [
          "${runtime}/piano-hardware-prepare --check-board"
          "${runtime}/touch-start"
        ];
        ExecStart = "${runtime}/touch-input";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 60;
      };
    };

    piano-radio =
      (unit {
        description = "Piano WLAN and Bluetooth";
        command = "radio-start";
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
        command = "adsp-start";
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
        command = "audio-start";
        after = [ "piano-adsp.service" ];
        timeout = 120;
      })
      // {
        wants = [ "piano-adsp.service" ];
      };

    piano-keyboard =
      (unit {
        description = "Piano keyboard cover";
        command = "keyboard-start";
        after = [
          "piano-touch.service"
          "piano-display.service"
        ];
        timeout = 60;
      })
      // {
        wants = [
          "piano-touch.service"
          "piano-display.service"
        ];
      };

    piano-cpufreq = unit {
      description = "Piano CPU frequency boost";
      command = "cpufreq-start";
      after = [ "systemd-modules-load.service" ];
      timeout = 60;
    };
  };
}
