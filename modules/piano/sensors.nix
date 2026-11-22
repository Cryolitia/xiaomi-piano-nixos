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

  numberedTemps =
    prefix: label: count:
    lib.concatMapStrings (i: ''
      chip "${prefix}${toString i}_thermal-*"
        label temp1 "${label} ${toString i}"
    '') (lib.range 0 (count - 1));

  cpuTemps =
    cluster: firstCpu: count:
    lib.concatMapStrings (
      core: numberedTemps "cpu_${cluster}_${toString core}_" "CPU ${toString (firstCpu + core)} 测点" 2
    ) (lib.range 0 (count - 1));
in
{
  environment.etc."sensors.d/piano.conf".text = ''
    chip "battery-*"
      label in0 "电池组电压"
      label temp1 "电池组温度"

    chip "bq27z561_0-*"
      label in0 "电芯 0 电压"
      label temp1 "电芯 0 温度"

    chip "bq27z561_1-*"
      label in0 "电芯 1 电压"
      label temp1 "电芯 1 温度"

    chip "piano_mca_usb-*"
      label in0 "USB 输入电压"

    chip "ucsi_source_psy_pmic_glink.ucsi.01-*"
      label in0 "USB-C 协议电压"

    chip "sc8541-*"
      label in0 "充电泵输入电压"
      label temp1 "充电泵芯片温度"
  ''
  + cpuTemps "0" 0 6
  + cpuTemps "1" 6 2
  + numberedTemps "cpuss_0_" "CPU 子系统 0 测点" 2
  + numberedTemps "cpuss_1_" "CPU 子系统 1 测点" 2
  + numberedTemps "gpuss" "GPU 测点" 8
  + numberedTemps "camera" "SoC 相机单元" 2
  + numberedTemps "modem" "基带测点" 4
  + numberedTemps "aoss" "常开子系统测点" 4
  + numberedTemps "nsphvx" "NSP HVX 测点" 3
  + numberedTemps "nsphmx" "NSP HMX 测点" 4
  + ''
    chip "video_thermal-*"
      label temp1 "SoC 视频单元"

    chip "ddr_thermal-*"
      label temp1 "DDR 子系统"

    chip "ath12k_hwmon-*"
      label temp1 "Wi-Fi 芯片"
  '';

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
        "piano-sensors-import.service"
        fastrpcDevice
      ];
      after = [
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
