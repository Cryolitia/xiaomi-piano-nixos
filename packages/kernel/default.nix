args@{
  lib,
  buildLinux,
  applyPatches,
  buildPackages,
  callPackage,
  fetchgit,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
  structuredExtraConfig ? { },
  ...
}:

let
  policy = builtins.fromJSON (builtins.readFile (sunuefiSrc + "/config/release.json"));
  seriesFile = policy.kernel.patch_series;
  patchDirectory = builtins.dirOf seriesFile;
  series = builtins.fromJSON (builtins.readFile (sunuefiSrc + "/${seriesFile}"));
  # Unrelated UEFI, device-tree and runtime changes must not rebuild Linux.
  kernelInputs = lib.cleanSourceWith {
    name = "piano-kernel-inputs";
    src = sunuefiSrc;
    filter =
      path: type:
      lib.any
        (
          relative:
          let
            selected = toString sunuefiSrc + "/${relative}";
          in
          path == selected
          || lib.hasPrefix (selected + "/") path
          || (type == "directory" && lib.hasPrefix (path + "/") selected)
        )
        [
          patchDirectory
          "linux/configs"
        ];
  };
  # A source revision alone is insufficient: preserve the ordered series and
  # verify each patch in the pinned source before handing it to the builder.
  # Evaluation can run before the filtered build input exists in the store.
  checkedPatch =
    entry:
    let
      relative = "${patchDirectory}/${entry.file}";
    in
    assert builtins.hashFile "sha256" (sunuefiSrc + "/${relative}") == entry.sha256;
    kernelInputs + "/${relative}";

  source = applyPatches {
    name = "linux-piano-source";
    src = fetchgit {
      name = "source";
      url = series.source_url;
      rev = series.base_commit;
      hash = "sha256-P+bNjwB204gzpltpfbI6PvV2uxPagElQIKVJopjhx/8=";
    };
    patches = map checkedPatch series.patches ++ [
      ./patches/0001-MAILLIST-media-iris-decode-order.patch
      ./patches/0002-MAILLIST-media-iris-capture-pool.patch
      ./patches/0003-MAILLIST-media-iris-encoder-deblocking.patch
      ./patches/0004-MAILLIST-media-iris-error-timestamps.patch
      ./patches/0005-MAILLIST-media-iris-recycle-noshow.patch
      ./patches/cpufreq-scmi-piano-boost-default.patch
    ];
    postPatch = ''
      ${buildPackages.python3.interpreter} ${./config.py} . ${kernelInputs}
    '';
  };

  overrides = builtins.removeAttrs args [
    "lib"
    "buildLinux"
    "applyPatches"
    "buildPackages"
    "callPackage"
    "fetchgit"
    "sunuefiSrc"
    "structuredExtraConfig"
    "extraMeta"
  ];

  # Keep the standard buildLinux override interface: NixOS adds kernel patches,
  # feature flags and its reproducible randomization seed through it.
  kernel = buildLinux (
    {
      version = series.kernel_version;
      modDirVersion = "${series.kernel_version}-piano-nixos";
      src = source;
      defconfig = "piano_nixos_defconfig";
      autoModules = false;
      # Nixpkgs' common config includes options removed from this newer kernel.
      # The required Piano and NixOS options are checked after configuration.
      ignoreConfigErrors = true;
    }
    // overrides
    // {
      structuredExtraConfig = lib.mkMerge [
        structuredExtraConfig
        (with lib.kernel; {
          LOCALVERSION = lib.mkForce (freeform "-piano-nixos");
          LOCALVERSION_AUTO = lib.mkForce no;

          # Boot arguments and initrd are supplied by the importing NixOS
          # system. Keep the standard EFI entry and initrd formats available.
          CMDLINE = lib.mkForce (freeform "");
          CMDLINE_FROM_BOOTLOADER = lib.mkForce yes;
          CMDLINE_FORCE = lib.mkForce no;
          CMDLINE_EXTEND = lib.mkForce no;
          EFI = lib.mkForce yes;
          EFI_STUB = lib.mkForce yes;
          BLK_DEV_INITRD = lib.mkForce yes;
          RD_GZIP = lib.mkForce yes;
          RD_XZ = lib.mkForce yes;
          RD_ZSTD = lib.mkForce yes;

          DEVTMPFS = lib.mkForce yes;
          DEVTMPFS_MOUNT = lib.mkForce yes;
          EXT4_FS = lib.mkForce yes;
          NAMESPACES = lib.mkForce yes;
          USER_NS = lib.mkForce yes;
          CGROUPS = lib.mkForce yes;
          FHANDLE = lib.mkForce yes;
          SECCOMP = lib.mkForce yes;
          SECCOMP_FILTER = lib.mkForce yes;
          SECURITY_LANDLOCK = lib.mkForce yes;
          OVERLAY_FS = lib.mkDefault module;
          SQUASHFS = lib.mkDefault module;
          RUST = lib.mkForce no;

          # NixOS' default firewall uses packet-type and reverse-path matches
          # for both IPv4 and IPv6, including with the nftables backend.
          NETFILTER_XT_MATCH_PKTTYPE = lib.mkDefault module;
          IP_NF_MATCH_RPFILTER = lib.mkDefault module;
          IP6_NF_MATCH_RPFILTER = lib.mkDefault module;

          # Keep the storage-only initrd small. Other board drivers are loaded
          # by their ordinary device aliases once the full module tree is mounted.
          ARM_SMMU = lib.mkForce module;
          DRM_MSM = lib.mkForce module;
          QCOM_Q6V5_PAS = lib.mkForce module;
          QCOM_PMIC_GLINK = lib.mkForce module;
          PINCTRL_SM8750 = lib.mkForce module;
          QCOM_GPI_DMA = lib.mkForce module;
          I2C_QCOM_GENI = lib.mkForce module;
          SPI_QCOM_GENI = lib.mkForce module;
          PHY_QCOM_QMP_PCIE = lib.mkForce module;
          SCSI_UFSHCD = lib.mkForce module;
          SCSI_UFS_QCOM = lib.mkForce module;
          PHY_QCOM_QMP_UFS = lib.mkForce module;

          # MCA provides the board's charging protocol. BATTMGR matches the
          # same GLINK auxiliary device and must not compete for that endpoint.
          BATTERY_QCOM_BATTMGR = lib.mkForce no;
        })
      ];
      extraMeta = {
        description = "Linux for Xiaomi Pad 8 Pro with the pinned Piano hardware patch series";
        platforms = [ "aarch64-linux" ];
      }
      // (args.extraMeta or { });
    }
  );
in
kernel.overrideAttrs (old: {
  postConfigure = (old.postConfigure or "") + ''
    piano_config="$buildRoot/.config"

    # Check the final Kconfig result, rather than trusting requested settings
    # that the upstream kernel may have renamed or made conditional.
    for setting in MODULES BLK_DEV_INITRD RD_XZ DEVTMPFS CGROUPS FHANDLE SECCOMP EXT4_FS \
                   IIO BATTERY_BQ27XXX_IIO QCOM_SPMI_ADC5_GEN3 EROFS_FS_ZIP \
                   BPF_LSM DEBUG_INFO_BTF; do
      grep -qx "CONFIG_$setting=y" "$piano_config" || {
        echo "Missing required Piano/NixOS kernel setting: $setting" >&2
        exit 1
      }
    done

    # With an empty CMDLINE, oldconfig drops the inactive command-line
    # choice. The effective string and absence of FORCE determine boot policy.
    grep -qx 'CONFIG_CMDLINE=""' "$piano_config"
    ! grep -qx 'CONFIG_CMDLINE_FORCE=y' "$piano_config"

    # Require the firewall matches and the shared filesystem and media drivers.
    for setting in NETFILTER_XT_MATCH_PKTTYPE IP_NF_MATCH_RPFILTER IP6_NF_MATCH_RPFILTER \
                   EROFS_FS VIDEO_DW9768 CHARGER_SC96231; do
      grep -Eq "^CONFIG_$setting=[ym]$" "$piano_config" || {
        echo "Missing required Piano/NixOS kernel setting: $setting" >&2
        exit 1
      }
    done

    # Both drivers claim pmic_glink.power-supply; only MCA may bind here.
    grep -qx '# CONFIG_BATTERY_QCOM_BATTMGR is not set' "$piano_config"

    # These drivers must remain available to the storage-only initrd and the
    # subsequent ordinary module autoloading pass.
    for setting in ARM_SMMU DRM_MSM QCOM_Q6V5_PAS QCOM_PMIC_GLINK PINCTRL_SM8750 \
                   QCOM_GPI_DMA I2C_QCOM_GENI SPI_QCOM_GENI PHY_QCOM_QMP_PCIE \
                   SCSI_UFSHCD SCSI_UFS_QCOM PHY_QCOM_QMP_UFS; do
      grep -qx "CONFIG_$setting=m" "$piano_config" || {
        echo "Piano driver must remain a loadable module: $setting" >&2
        exit 1
      }
    done
  '';
})
