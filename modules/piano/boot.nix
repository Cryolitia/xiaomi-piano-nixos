{
  config,
  lib,
  pkgs,
  pianoPackages,
  ...
}:

let
  storageModules = [
    "arm_smmu"
    "pinctrl_sm8750"
    "qcom_cpucp_mbox"
    "phy_qcom_qmp_ufs"
    "ufs_qcom"
  ];

  moduleOrderRules =
    systemdPackage:
    pkgs.runCommand "piano-module-order-rules" { } ''
      rules="$out/lib/udev/rules.d/80-drivers.rules"
      install -Dm644 ${systemdPackage}/lib/udev/rules.d/80-drivers.rules "$rules"

      # Refuse an upstream rule layout change instead of silently allowing
      # modalias autoloading to race the board's ordered platform units.
      kmod_rule='ENV{MODALIAS}=="?*", RUN{builtin}+="kmod load"'
      test "$(grep -Fc "$kmod_rule" "$rules")" -eq 1
      substituteInPlace "$rules" --replace-fail "$kmod_rule" \
        'ENV{MODALIAS}=="?*", ENV{MODALIAS}!="of:*|platform:*|amba:*|spmi:*|auxiliary:*|slim:*|rpmsg:*|qcom-*", RUN{builtin}+="kmod load"'
    '';
in
{
  # Root devices, filesystems, desktop and bootloader remain caller policy.
  boot.kernelPackages = lib.mkDefault pianoPackages.kernelPackages;

  hardware.deviceTree = {
    enable = lib.mkDefault true;
    dtbSource = lib.mkDefault pianoPackages.deviceTree;
    name = lib.mkDefault "piano.dtb";
  };

  boot.kernelParams = [
    "clk_ignore_unused"
    "pd_ignore_unused"
    "iommu.passthrough=1"
  ];

  # The board kernel omits drivers from NixOS' generic PC/VM module list.
  # Loading order is enforced by the storage service and udev rules below.
  boot.initrd.includeDefaultModules = lib.mkDefault false;
  boot.initrd.availableKernelModules = storageModules ++ [
    "sd_mod"
    "ext4"
  ];

  # Load the storage seeds with explicit modprobe calls in board order,
  # before the general udev coldplug pass.
  boot.initrd.systemd.services.piano-storage = {
    description = "Load Piano storage drivers in order";
    requiredBy = [
      "systemd-udev-trigger.service"
      "sysroot.mount"
    ];
    before = [
      "systemd-modules-load.service"
      "systemd-udev-trigger.service"
      "sysroot.mount"
    ];
    after = [
      "systemd-udevd-control.socket"
      "systemd-udevd-kernel.socket"
    ];
    requires = [
      "systemd-udevd-control.socket"
      "systemd-udevd-kernel.socket"
    ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 60;
    };
    script = ''
      set -eu
      for module in ${lib.concatStringsSep " " storageModules}; do
        /bin/modprobe "$module"
      done
    '';
  };

  # NixOS merges rule files by basename; put this copy after the standard
  # package. Only default SoC autoloading is skipped, not other udev actions.
  boot.initrd.services.udev.packages = lib.mkAfter [
    (moduleOrderRules config.boot.initrd.systemd.package)
  ];
  services.udev.packages = lib.mkAfter [ (moduleOrderRules config.systemd.package) ];

  boot.kernelModules = [
    "qcom_pon"
    "qcom_cpucp_mbox"
    "uhid"
    "hid_xiaomi"
    "piano_pen_dock"
    "nvmem_qcom_spmi_sdam"
    "leds_qcom_lpg"
    "rtc_pm8xxx"
    "sc96231_charger"
  ];

  # A modalias must not race the ordered display/radio/ADSP bring-up units.
  # Explicit modprobe calls still work; the reviewed kernel owns all DMA.
  boot.extraModprobeConfig = lib.replaceStrings [ "/bin/false" ] [ "${pkgs.coreutils}/bin/false" ] (
    builtins.readFile (pianoPackages.bsp.src + "/linux/bsp/common/etc/modprobe.d/piano.conf")
  );
}
