{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.xiaomi.piano;
  packages = import ../../packages { inherit pkgs; };
  deviceTree = packages.deviceTree.override {
    memoryGiB = cfg.memoryGiB;
  };
in
{
  imports = [
    ./boot.nix
    ./runtime.nix
    ./audio.nix
    ./camera.nix
    ./gnome.nix
    ./fingerprint.nix
    ./sensors.nix
  ];

  options.hardware.xiaomi.piano.memoryGiB = lib.mkOption {
    type = lib.types.enum [
      16
      24
    ];
    description = ''
      Physical RAM capacity in GiB for the validated static device-tree map.
      Current SunUEFI replaces RAM and DDR metadata with the layout supplied
      by this boot's firmware. The static selection also supports older
      firmware that requires the input map to match the device.
    '';
  };

  options.hardware.xiaomi.piano.pen.enable =
    lib.mkEnableOption "stylus input and Bluetooth pen configuration";

  config = {
    _module.args.pianoPackages = packages // {
      inherit deviceTree;
    };

    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

    # Gunyah makes automatic chassis detection report a VM. GNOME uses the
    # physical chassis to choose the power-key policy on this tablet.
    environment.etc."machine-info".text = "CHASSIS=tablet\n";
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isAarch64;
        message = "The Xiaomi Pad 8 Pro module requires aarch64-linux.";
      }
    ];

    hardware.firmware = [
      packages.firmware
      packages.bsp
    ];
    hardware.enableRedistributableFirmware = lib.mkDefault true;
    hardware.bluetooth.enable = lib.mkDefault true;

    hardware.graphics = {
      enable = lib.mkDefault true;
      package = lib.mkOverride 990 packages.mesa;
    };

  };
}
