{
  runCommand,
  python3,
  dosfstools,
  mtools,
  android-tools,
  libfaketime,
  systemd,
  bootFiles,
}:

runCommand "piano-nixos-esp.sparse.img"
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
      --output "$out"
  ''
