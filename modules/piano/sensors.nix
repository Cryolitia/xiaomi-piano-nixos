{
  config,
  lib,
  pkgs,
  pianoPackages,
  ...
}:

let
  sensors = pianoPackages.sensors;
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
      wantedBy = [ "multi-user.target" ];
      requires = [
        "piano-adsp.service"
        "piano-sensors-import.service"
      ];
      after = [
        "piano-adsp.service"
        "piano-sensors-import.service"
      ];
      before = [ "iio-sensor-proxy.service" ];
      path = [
        pkgs.kmod
        pkgs.coreutils
      ];
      preStart = ''
        modprobe socinfo
        modprobe fastrpc

        # The remoteproc publishes FastRPC asynchronously after ADSP starts.
        for attempt in $(seq 1 60); do
          if test -e /dev/fastrpc-adsp-secure; then
            exit 0
          fi
          sleep 1
        done

        echo "Piano ADSP FastRPC device did not appear" >&2
        exit 1
      '';
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
