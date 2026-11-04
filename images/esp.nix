{
  runCommand,
  python3,
  dosfstools,
  mtools,
  android-tools,
  libfaketime,
  systemd,
  bootFiles,
  linuxLoader,
}:

runCommand "piano-nixos-esp-image"
  {
    nativeBuildInputs = [
      python3
      dosfstools
      mtools
      android-tools
      libfaketime
    ];
  }
  ''
    export TZ=UTC MTOOLSRC=/dev/null
    faketime '1980-01-01 00:00:00' python3 ${./make-esp.py} \
      --boot-files ${bootFiles} \
      --systemd-boot ${systemd}/lib/systemd/boot/efi/systemd-bootaa64.efi \
      --linux-loader ${linuxLoader}/EFI/Piano/LinuxBoot.efi \
      --sparse-tool ${linuxLoader.src}/tools/package_sparse_images.py \
      --output "$out"
  ''
