{
  description = "NixOS hardware support and GNOME validation images for Xiaomi Pad 8 Pro (piano)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      configurations = {
        piano-gnome = lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            self.nixosModules.piano
            ./configurations/gnome.nix
            ./images
          ];
        };
      };

      # Check the importable module without the image's disk, desktop or
      # bootloader policy, separately from the complete GNOME configurations.
      hardwareOnly = lib.nixosSystem {
        system = "aarch64-linux";
        modules = [ self.nixosModules.piano ];
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
          ffmpeg = piano.ffmpeg;
          firmware = piano.firmware;
          device-tree = piano.deviceTree;
          gnome-image = configurations.piano-gnome.config.system.build.pianoImage;
          default = self.packages.aarch64-linux.gnome-image;
        };

      formatter = forSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);

      checks = forSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cfg = hardwareOnly.config;
          gnome = configurations.piano-gnome.config;
          powerOverlay = (import ./packages/sunuefi-source.nix { }) + "/linux/desktops/gnome/power-overlay";
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
            assert !(hardwareOnly.options ? piano.image);
            assert !(hardwareOnly.options ? sdImage);
            assert !(cfg.systemd.services ? piano-register-store);
            assert !(cfg.systemd.services ? register-nix-paths);
            assert !cfg.services.desktopManager.gnome.enable;
            assert !cfg.services.displayManager.gdm.enable;
            assert !cfg.services.tuned.enable;
            assert !cfg.services.power-profiles-daemon.enable;
            assert !cfg.boot.loader.external.enable;
            assert !(hardwareOnly.options.hardware.xiaomi.piano ? memoryGiB);
            assert builtins.attrNames configurations == [ "piano-gnome" ];
            assert gnome.services.tuned.enable && gnome.services.tuned.ppdSupport;
            assert !gnome.services.power-profiles-daemon.enable;
            assert gnome.services.upower.enable;
            assert
              gnome.environment.etc."tuned/ppd.conf".text
              == builtins.readFile (powerOverlay + "/etc/tuned/piano-ppd.conf");
            assert lib.all (
              name:
              gnome.environment.etc."tuned/profiles/${name}/tuned.conf".text
              == builtins.readFile (powerOverlay + "/usr/lib/tuned/profiles/${name}/tuned.conf")
            ) (builtins.attrNames (builtins.readDir (powerOverlay + "/usr/lib/tuned/profiles")));
            assert
              self.packages.aarch64-linux.default.drvPath
              == configurations.piano-gnome.config.system.build.pianoImage.drvPath;
            assert lib.all (
              configuration:
              let
                services = configuration.config.systemd.services;
              in
              services ? register-nix-paths
              && !(services ? piano-register-store)
              && services.register-nix-paths.unitConfig.ConditionPathExists == "/nix-path-registration"
            ) (lib.attrValues configurations);
            pkgs.writeText "piano-module-interface" "Hardware import keeps image services, disk, desktop and bootloader policy separate.\n";
        }
      );
    };
}
