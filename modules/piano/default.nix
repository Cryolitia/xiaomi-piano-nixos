{ sources }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.xiaomi.piano;
  packages = import ../../packages ({ inherit pkgs; } // sources);
  deviceTree = packages.deviceTree.override ({
    memoryLayout =
      if cfg.memoryGiB == 24 then ../../packages/device-tree/profiles/24gb-boe.json else null;
  });
in
{
  imports = [
    ./boot.nix
    ./runtime.nix
    ./audio.nix
  ];

  options.hardware.xiaomi.piano.memoryGiB = lib.mkOption {
    type = lib.types.enum [
      16
      24
    ];
    description = ''
      Physical RAM capacity in GiB. Selects the matching validated DDR map;
      the loader does not replace this map. Other capacities are rejected
      until their physical and reserved-memory layout has been established.
    '';
  };

  config = {
    _module.args.pianoPackages = packages // {
      inherit deviceTree;
    };
    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
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

    services.udev.packages = [ packages.bsp ];
  };
}
