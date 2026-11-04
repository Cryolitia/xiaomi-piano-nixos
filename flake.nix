{
  description = "NixOS hardware support and GNOME validation images for Xiaomi Pad 8 Pro (piano)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sunuefi-source = {
      url = "github:Cryolitia-Forks/Project-SunUEFI/874ef77d11c9616edda656d9fcd135364fb37d32";
      flake = false;
    };
    linux-source = {
      url = "github:torvalds/linux/c03c1a14507dfaf8b856c2608f9ac216021fc222";
      flake = false;
    };
    debian-piano = {
      url = "github:blu-sharky/debian-piano/a75f8c5d5fa099d65c171ac839c2e3bb6c63ec45";
      flake = false;
    };
    piano-firmware = {
      url = "github:blu-sharky/piano-firmware/05fc37c09ca8146eecfc4920f8485479db140ae5";
      flake = false;
    };
    mesa-patches = {
      url = "github:blu-sharky/piano-mesa/a89c1e46eef3e161520b084479928aaa5a8e8732";
      flake = false;
    };
    audioreach-topology = {
      url = "github:linux-msm/audioreach-topology/993a17dcb672357998a463a73f120064d6c74f4f";
      flake = false;
    };
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      sources = {
        sunuefiSrc = inputs.sunuefi-source;
        linuxSrc = inputs.linux-source;
        debianPianoSrc = inputs.debian-piano;
        firmwareSrc = inputs.piano-firmware;
        mesaPatchesSrc = inputs.mesa-patches;
        audioReachSrc = inputs.audioreach-topology;
      };
      lib = nixpkgs.lib;
      mkValidation =
        extraModules:
        lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            self.nixosModules.piano
            ./configurations/gnome.nix
            ./images
          ]
          ++ extraModules;
        };
      configurations = {
        piano-gnome = mkValidation [ ];
        piano-24gb-gnome = mkValidation [ { hardware.xiaomi.piano.memoryGiB = 24; } ];
      };
      hardwareOnly = lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          self.nixosModules.piano
          { hardware.xiaomi.piano.memoryGiB = 16; }
        ];
      };
      forSystems = lib.genAttrs [
        "aarch64-linux"
        "x86_64-linux"
      ];
    in
    {
      nixosModules = {
        piano = import ./modules/piano { inherit sources; };
        default = self.nixosModules.piano;
      };
      nixosConfigurations = configurations;

      packages.aarch64-linux =
        let
          pkgs = import nixpkgs {
            system = "aarch64-linux";
            config.allowUnfree = true;
          };
          piano = import ./packages ({ inherit pkgs; } // sources);
        in
        {
          kernel = piano.kernel;
          firmware = piano.firmware;
          linux-loader = piano.linuxLoader;
          device-tree = piano.deviceTree;
          gnome-image = configurations.piano-gnome.config.system.build.pianoImage;
          gnome-24gb-image = configurations.piano-24gb-gnome.config.system.build.pianoImage;
          boot-files = configurations.piano-gnome.config.system.build.pianoBootFiles;
          esp-image = configurations.piano-gnome.config.system.build.pianoEspImage;
          esp-24gb-image = configurations.piano-24gb-gnome.config.system.build.pianoEspImage;
          default = self.packages.aarch64-linux.gnome-image;
        };

      formatter = forSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);

      checks = forSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cfg = hardwareOnly.config;
        in
        {
          linux-loader = pkgs.callPackage ./packages/linux-loader { inherit (sources) sunuefiSrc; };
          module-interface =
            assert !(cfg.fileSystems ? "/");
            assert !cfg.services.desktopManager.gnome.enable;
            assert !cfg.services.displayManager.gdm.enable;
            assert !cfg.boot.loader.external.enable;
            assert configurations.piano-gnome.config.hardware.xiaomi.piano.memoryGiB == 16;
            assert configurations.piano-24gb-gnome.config.hardware.xiaomi.piano.memoryGiB == 24;
            pkgs.writeText "piano-module-interface" "Hardware import keeps disk, desktop and bootloader policy separate.\n";
        }
      );
    };
}
