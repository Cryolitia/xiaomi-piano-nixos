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

  hardware.bluetooth.package = lib.mkIf config.hardware.bluetooth.enable (
    lib.mkDefault (pkgs.callPackage ../../packages/bluez { sunuefiSrc = pianoSunuefiSrc; })
  );

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
  };
}
