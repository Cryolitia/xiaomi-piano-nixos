{
  config,
  lib,
  pianoPackages,
  ...
}:

let
  runtime = "${pianoPackages.bsp}/libexec/piano";
  unit = description: command: after: timeout: {
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

  systemd.services = {
    piano-display =
      (unit "Piano native display and GPU" "display-start --all" [ "systemd-udev-trigger.service" ] 240)
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
      (unit "Piano WLAN and Bluetooth" "radio-start" [
        "systemd-udev-trigger.service"
        "piano-touch.service"
      ] 180)
      // {
        wants = [ "piano-touch.service" ];
        before = [ "bluetooth.service" ];
      };
    bluetooth = lib.mkIf config.hardware.bluetooth.enable {
      wants = [ "piano-radio.service" ];
      after = [ "piano-radio.service" ];
    };
    piano-adsp =
      (unit "Piano ADSP and charging" "adsp-start" [
        "systemd-udev-trigger.service"
        "piano-display.service"
        "piano-touch.service"
      ] 120)
      // {
        requires = [ "piano-display.service" ];
      };
    piano-audio = (unit "Piano sound card" "audio-start" [ "piano-adsp.service" ] 120) // {
      wants = [ "piano-adsp.service" ];
    };
    piano-keyboard =
      (unit "Piano keyboard cover" "keyboard-start" [ "piano-touch.service" "piano-display.service" ] 60)
      // {
        wants = [
          "piano-touch.service"
          "piano-display.service"
        ];
      };
    piano-cpufreq = unit "Piano CPU frequency boost" "cpufreq-start" [
      "systemd-modules-load.service"
    ] 60;

  };
}
