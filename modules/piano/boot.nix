{
  lib,
  pkgs,
  pianoPackages,
  ...
}:

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
  boot.initrd.availableKernelModules = [
    "arm_smmu"
    "pinctrl_sm8750"
    "qcom_cpucp_mbox"
    "phy_qcom_qmp_ufs"
    "ufs_qcom"
    "ext4"
  ];
  boot.initrd.kernelModules = [
    "arm_smmu"
    "pinctrl_sm8750"
    "qcom_cpucp_mbox"
    "phy_qcom_qmp_ufs"
    "ufs_qcom"
  ];
  boot.initrd.services.udev.packages = [ pianoPackages.bsp ];
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
