{
  description = "NixOS hardware support and GNOME validation images for Xiaomi Pad 8 Pro (piano)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
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

      # Check the importable module without the image's disk, desktop or
      # bootloader policy, separately from the complete GNOME configurations.
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
        piano = import ./modules/piano;
        default = self.nixosModules.piano;
      };
      nixosConfigurations = configurations;

      packages.aarch64-linux =
        let
          pkgs = import nixpkgs {
            system = "aarch64-linux";
            config.allowUnfree = true;
          };
          piano = import ./packages { inherit pkgs; };
        in
        {
          kernel = piano.kernel;
          firmware = piano.firmware;
          device-tree = piano.deviceTree;
          gnome-image = configurations.piano-gnome.config.system.build.pianoImage;
          gnome-24gb-image = configurations.piano-24gb-gnome.config.system.build.pianoImage;
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
          scripts-format =
            pkgs.runCommand "piano-scripts-format"
              {
                nativeBuildInputs = [ pkgs.ruff ];
              }
              ''
                ruff format --check --no-cache --config ${self}/ruff.toml ${self}
                ruff check --no-cache --config ${self}/ruff.toml ${self}
                touch "$out"
              '';

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
