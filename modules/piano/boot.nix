{
  lib,
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

  # The ordinary udev coldplug pass probes these devices. Firmware resources
  # and deferred probing determine their order, including GPUCC before SMMU.
  boot.initrd.includeDefaultModules = lib.mkDefault false;
  boot.initrd.availableKernelModules = [
    "gpucc_sm8750"
    "arm_smmu"
    "pinctrl_sm8750"
    "phy_qcom_qmp_ufs"
    "ufs_qcom"
    "sd_mod"
    "ext4"
  ];

  # Virtual input interfaces have no physical device alias to trigger loading.
  boot.kernelModules = [
    "uhid"
    "uinput"
  ];

  # These are driver policies, not a userspace module-loading sequence.
  # DT disables unsupported devices; normal aliases remain enabled on all buses.
  boot.extraModprobeConfig = ''
    options msm separate_gpu_kms=1
    options hci_uart piano_retries=0 piano_peri=106
    options piano_mca charge_policy=1 hv_charge=1 charge_current=1 pan_ack=0 mipps_auth=1 cp_charge=1
  '';
}
