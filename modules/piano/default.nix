{
  lib,
  pkgs,
  ...
}:

let
  packages = import ../../packages { inherit pkgs; };
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

  options.hardware.xiaomi.piano.pen.enable =
    lib.mkEnableOption "stylus input and Bluetooth pen configuration";

  config = {
    _module.args.pianoPackages = packages;

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
