{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  cfg = config.piano.image;
  inherit (lib) mkDefault mkOption types;
  # Build the initial boot entry from the same system that populates root.
  bootFiles =
    pkgs.runCommand "piano-linux-boot-files"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 ${./make-boot-files.py} ${config.system.build.toplevel} "$out"
      '';

  # make-ext4-fs supplies the closure and its registration database.
  rootFilesystem = pkgs.callPackage (pkgs.path + "/nixos/lib/make-ext4-fs.nix") {
    storePaths = [ config.system.build.toplevel ];
    compressImage = false;
    volumeLabel = "PIANOROOT";
    uuid = "bcf81013-f76b-4b85-9d3c-7f6423034bbc";
    populateImageCommands = ''
      mkdir -p ./files/{boot,etc,nix/var/nix/profiles}
    '';
  };

  espImage = pkgs.callPackage ./esp.nix {
    inherit bootFiles;
  };

  image =
    pkgs.runCommand "piano-nixos-gnome-image"
      {
        nativeBuildInputs = with pkgs; [
          android-tools
          coreutils
          e2fsprogs
          gnutar
          python3
          util-linux
        ];
      }
      ''
        python3 ${./make-image.py} \
          --boot-files ${bootFiles} \
          --esp-image ${espImage} \
          --root-filesystem ${rootFilesystem} \
          --root-size-mib ${toString cfg.rootSizeMiB} \
          --system ${config.system.build.toplevel} \
          --output "$out"
      '';
in
{
  options = {
    piano.image.rootSizeMiB = mkOption {
      type = types.ints.positive;
      default = 16384;
      description = "Size of the standalone ext4 validation image, in MiB.";
    };
  };

  config = {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isAarch64;
        message = "The Piano validation image requires aarch64-linux.";
      }
      {
        assertion = config.boot.initrd.secrets == { };
        message = "The validation image cannot include initrd secrets in the public ESP boot payload.";
      }
    ];

    boot.initrd = {
      compressor = mkDefault "xz";
      compressorArgs = mkDefault (
        if builtins.isString config.boot.initrd.compressor && config.boot.initrd.compressor == "xz" then
          [
            "-9e"
            "--check=crc32"
            "--threads=1"
          ]
        else
          null
      );
    };

    boot.kernelParams = [
      "rootfstype=ext4"
      "rootwait"
    ];
    boot.supportedFilesystems = [
      "ext4"
      "vfat"
    ];

    # Runtime updates use NixOS itself; the Python tools only build offline images.
    boot.loader.systemd-boot = {
      enable = true;
      installDeviceTree = true;
      configurationLimit = mkDefault 5;
      editor = false;
    };
    boot.loader.timeout = mkDefault 15;
    boot.loader.efi.efiSysMountPoint = "/boot";
    boot.loader.generic-extlinux-compatible.enable = false;
    boot.loader.efi.canTouchEfiVariables = false;

    fileSystems = {
      "/" = {
        device = "/dev/disk/by-partlabel/sunuefi_root";
        fsType = "ext4";
        autoResize = true;
      };
      "/boot" = {
        device = "/dev/disk/by-partlabel/sunuefi_esp";
        fsType = "vfat";
        options = [
          "nosuid"
          "nodev"
          "noexec"
        ];
      };
    };

    # Select nixpkgs' first-boot unit without importing the SD image layout.
    systemd.services.register-nix-paths =
      (import (modulesPath + "/installer/sd-card/sd-image.nix") {
        inherit lib pkgs;
        config = {
          nix.package = config.nix.package;
          sdImage.nixPathRegistrationFile = "/nix-path-registration";
        };
      }).config.systemd.services.register-nix-paths;

    system.build.pianoImage = image;
  };
}
