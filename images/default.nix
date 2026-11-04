{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.piano.image;
  inherit (lib) mkDefault mkOption types;
  rootDevice = config.fileSystems."/".device;
  rootDeviceName = utils.escapeSystemdPath rootDevice;
  rootDeviceUnit = "${rootDeviceName}.device";
  rootFsckUnit = "systemd-fsck@${rootDeviceName}.service";
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

    system.build.installBootLoader = mkOption {
      # Keep the standard NixOS updater; only check the image's dedicated
      # partition identities before it can write the ESP.
      apply =
        installer:
        pkgs.writeShellScript "install-piano-systemd-boot" ''
          set -euo pipefail
          export PATH=${
            lib.makeBinPath [
              pkgs.coreutils
              pkgs.util-linuxMinimal
            ]
          }

          fail() {
            echo "Piano boot update refused: $*" >&2
            exit 1
          }

          # Resolve the actual mounts before the standard installer can write.
          # Filesystem labels alone cannot establish partition ownership.
          esp=${lib.escapeShellArg config.boot.loader.efi.efiSysMountPoint}
          device=$(findmnt --noheadings --raw --output SOURCE --mountpoint "$esp") ||
            fail 'Mount the SunUEFI ESP before updating.'
          test -b "$device" || fail 'The ESP is not a block-device filesystem.'
          test "$(blkid -p -s PART_ENTRY_NAME -o value "$device")" = sunuefi_esp ||
            fail 'The ESP is not the sunuefi_esp partition.'
          test "$(blkid -p -s LABEL -o value "$device")" = SUNUEFI_ESP ||
            fail 'The ESP filesystem label is not SUNUEFI_ESP.'
          test "$(findmnt --noheadings --raw --output FSTYPE --mountpoint "$esp")" = vfat ||
            fail 'The ESP must use FAT32.'

          root_device=$(findmnt --noheadings --raw --output SOURCE --mountpoint /)
          test -b "$root_device" || fail 'The root is not a block-device filesystem.'
          test "$(blkid -p -s PART_ENTRY_NAME -o value "$root_device")" = sunuefi_root ||
            fail 'The root is not the sunuefi_root partition.'
          test "$(blkid -p -s LABEL -o value "$root_device")" = PIANOROOT ||
            fail 'The root filesystem label is not PIANOROOT.'
          test "$(findmnt --noheadings --raw --output FSTYPE --mountpoint /)" = ext4 ||
            fail 'The root must use ext4.'

          # Both filesystems must belong to the same physical storage device.
          test "$(lsblk --noheadings --raw --output PKNAME "$root_device")" = \
            "$(lsblk --noheadings --raw --output PKNAME "$device")" ||
            fail 'The ESP and root must belong to the same disk.'

          exec ${installer} "$@"
        '';
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

    # Check the dedicated root identity before fsck or automatic filesystem growth.
    boot.initrd = {
      systemd.extraBin.blkid = "${config.boot.initrd.systemd.package.util-linux}/bin/blkid";
      systemd.services.piano-check-root = {
        description = "Check the Piano root partition before filesystem access";
        requiredBy = [
          "sysroot.mount"
          "systemd-fsck-root.service"
          rootFsckUnit
        ];
        before = [
          "sysroot.mount"
          "systemd-fsck-root.service"
          rootFsckUnit
        ];
        after = [ rootDeviceUnit ];
        requires = [ rootDeviceUnit ];
        bindsTo = [ rootDeviceUnit ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          fail() {
            echo "Piano root refused: $*" >&2
            exit 1
          }

          # This gate runs in stage 1, where only the selected block device
          # and blkid are needed; it does not mount or modify the partition.
          device=${lib.escapeShellArg rootDevice}
          test -b "$device" || fail 'The selected root is not a block device.'
          test "$(/bin/blkid -p -s TYPE -o value "$device")" = ext4 ||
            fail 'The selected root does not contain ext4.'
          test "$(/bin/blkid -p -s LABEL -o value "$device")" = PIANOROOT ||
            fail 'The selected root is not labelled PIANOROOT.'
          test "$(/bin/blkid -p -s PART_ENTRY_NAME -o value "$device")" = sunuefi_root ||
            fail 'The selected root is not the sunuefi_root partition.'
        '';
      };

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
    boot.loader.timeout = mkDefault 0;
    boot.loader.efi.efiSysMountPoint = "/boot";
    boot.loader.generic-extlinux-compatible.enable = false;
    boot.loader.efi.canTouchEfiVariables = false;

    fileSystems = {
      "/" = {
        device = "/dev/disk/by-label/PIANOROOT";
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

    # Import the image registration once before the Nix daemon starts.
    systemd.services.piano-register-store = {
      description = "Register the Nix store from the initial Piano image";
      wantedBy = [ "sysinit.target" ];
      after = [ "local-fs.target" ];
      before = [
        "sysinit.target"
        "nix-daemon.service"
        "nix-daemon.socket"
      ];
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "/nix-path-registration";
        RequiresMountsFor = [
          "/nix/store"
          "/nix/var/nix"
        ];
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        config.nix.package
        pkgs.coreutils
      ];
      script = ''
        nix-store --load-db < /nix-path-registration

        touch /etc/NIXOS
        nix-env -p /nix/var/nix/profiles/system --set /run/current-system

        # Removing the marker makes subsequent boots leave the live database alone.
        rm -f /nix-path-registration
      '';
    };

    system.build.pianoImage = image;
  };
}
