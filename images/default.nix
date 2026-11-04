{
  config,
  lib,
  pkgs,
  pianoPackages,
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
  bootTools = pkgs.writeShellApplication {
    name = "piano-make-boot-files";
    runtimeInputs = with pkgs; [
      android-tools
      coreutils
      python3
    ];
    text = builtins.readFile ./make-boot-files.sh;
  };
  installBootFiles = pkgs.writeShellApplication {
    name = "piano-install-boot-files";
    runtimeInputs = [
      bootTools
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = builtins.readFile ./install-boot-files.sh;
  };
  bootFiles =
    pkgs.runCommand "piano-linux-boot-files"
      {
        nativeBuildInputs = [ bootTools ];
      }
      ''
        piano-make-boot-files ${config.system.build.toplevel} \
          ${config.hardware.deviceTree.package}/piano.dtb "$out"
      '';
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
    linuxLoader = pianoPackages.linuxLoader;
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
        mkdir -p "$out/boot-files"
        cp -rL ${bootFiles}/. "$out/boot-files/"
        cp --sparse=always ${espImage}/esp.img "$out/esp.img"
        cp ${espImage}/esp.sparse.img "$out/esp.sparse.img"
        cp --sparse=always ${rootFilesystem} "$out/root.ext4.img"
        target_bytes=$((${toString cfg.rootSizeMiB} * 1024 * 1024))
        if [ "$(stat -c %s "$out/root.ext4.img")" -gt "$target_bytes" ]; then
          echo 'The NixOS closure exceeds piano.image.rootSizeMiB; increase the image size.' >&2
          exit 1
        fi
        truncate -s "$target_bytes" "$out/root.ext4.img"
        resize2fs -f "$out/root.ext4.img"
        e2fsck -f -n "$out/root.ext4.img"
        test "$(blkid -p -s LABEL -o value "$out/root.ext4.img")" = PIANOROOT
        img2simg "$out/root.ext4.img" "$out/root.sparse.img" 4096
        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
          -C "$out/boot-files" -cf "$out/boot-files.tar" EFI loader
        python3 - "$out" "$target_bytes" <<'PY'
        import hashlib
        import json
        from pathlib import Path
        import sys
        out = Path(sys.argv[1])
        esp = json.loads(Path('${espImage}/manifest.json').read_text())
        files = {}
        for name in ('root.ext4.img', 'root.sparse.img', 'esp.img', 'esp.sparse.img', 'boot-files.tar'):
            with (out / name).open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            files[name] = {'bytes': (out / name).stat().st_size, 'sha256': digest}
        (out / 'manifest.json').write_text(json.dumps({
            'schemaVersion': 1,
            'system': '${config.system.build.toplevel}',
            'rootPartition': 'sunuefi_root',
            'rootLabel': 'PIANOROOT',
            'expandedRootBytes': int(sys.argv[2]),
            'espPartition': esp['espPartition'],
            'espLabel': esp['espLabel'],
            'expandedEspBytes': esp['expandedEspBytes'],
            'espSectorBytes': esp['sectorBytes'],
            'bootFilesDirectory': '/EFI/Piano/stable',
            'files': files,
        }, indent=2) + '\n')
        PY
        cd "$out"
        sha256sum root.ext4.img root.sparse.img esp.img esp.sparse.img boot-files.tar manifest.json > SHA256SUMS
      '';
in
{
  options.piano.image.rootSizeMiB = mkOption {
    type = types.ints.positive;
    default = 16384;
    description = "Size of the standalone ext4 validation image, in MiB.";
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
      # NixOS includes systemd-bsod in the initrd; its build requires QR encoding.
      systemd.package = mkDefault (pkgs.systemdMinimal.override { withQrencode = true; });
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
          fail() { echo "Piano root refused: $*" >&2; exit 1; }
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
    boot.loader.external = {
      enable = true;
      installHook = "${installBootFiles}/bin/piano-install-boot-files";
    };
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
        rm -f /nix-path-registration
      '';
    };
    system.build = {
      pianoBootFiles = bootFiles;
      pianoEspImage = espImage;
      pianoRootfs = rootFilesystem;
      pianoImage = image;
    };
  };
}
