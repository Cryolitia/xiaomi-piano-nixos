{
  config,
  lib,
  pkgs,
  pianoPackages,
  utils,
  ...
}:

let
  sensors = pianoPackages.sensors;
  fastrpcDevice = "${utils.escapeSystemdPath "/dev/fastrpc-adsp-secure"}.device";
in
{
  # SSC is a backend of standard SensorProxy; Mutter remains responsible
  # for the display, touch/pen transforms and genuine tablet-mode policy.
  hardware.sensor.iio = {
    enable = lib.mkDefault true;
    package = lib.mkDefault sensors.sensorProxy;
  };

  # The generic IIO option includes this PC/HID driver in the initrd.
  # Piano's SSC backend uses QRTR/FastRPC and the board kernel omits it.
  boot.initrd.availableKernelModules.hid-sensor-hub = lib.mkForce false;

  services.udev.packages = lib.mkIf config.hardware.sensor.iio.enable [ sensors.runtime ];
  environment.systemPackages = lib.mkIf config.hardware.sensor.iio.enable [ sensors.runtime ];

  systemd.services = lib.mkIf config.hardware.sensor.iio.enable {
    piano-sensors-import = {
      description = "Import this tablet's sensor configuration";
      after = [
        "local-fs.target"
        "systemd-udev-trigger.service"
      ];
      before = [ "adsprpcd-sensorspd.service" ];
      path = [ pkgs.lvm2 ];
      postStop = ''
        # Device-mapper devices outlive mount namespaces if import is killed.
        for mapping in piano-sensors-odm piano-sensors-vendor; do
          dmsetup remove "$mapping" 2>/dev/null || true
        done
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 180;
        ExecStart = "${sensors.runtime}/bin/piano-sensors-import";
        StateDirectory = "piano-sensors";
        RuntimeDirectory = "piano-sensors";
        PrivateMounts = true;
      };
    };

    adsprpcd-sensorspd = {
      description = "Piano ADSP sensor service";
      wantedBy = [ fastrpcDevice ];
      requires = [
        "piano-adsp.service"
        "piano-sensors-import.service"
        fastrpcDevice
      ];
      after = [
        "piano-adsp.service"
        "piano-sensors-import.service"
        fastrpcDevice
      ];
      before = [ "iio-sensor-proxy.service" ];
      # SensorProxy's udev rule tags FastRPC for systemd. The device starts
      # this service once ADSP publishes it; normal aliases load the drivers.
      serviceConfig = {
        Type = "exec";
        ExecStart = "${sensors.fastrpc}/bin/adsprpcd sensorspd";
        ExecStartPost = "${sensors.runtime}/bin/piano-sensors-wait";
        TimeoutStartSec = 180;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    iio-sensor-proxy = {
      wants = [ "adsprpcd-sensorspd.service" ];
      after = [ "adsprpcd-sensorspd.service" ];
    };
  };
}
