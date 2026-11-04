{
  lib,
  stdenvNoCC,
  llvmPackages,
  edk2,
  callPackage,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
}:

stdenvNoCC.mkDerivation {
  pname = "piano-linux-loader";
  version = "1";
  src = sunuefiSrc;
  nativeBuildInputs = [
    llvmPackages.clang-unwrapped
    llvmPackages.lld
  ];
  dontConfigure = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    pump=uefi/components/product-pump/Mu_Basecore/MdePkg
    headers=${edk2.srcWithVendoring}/MdePkg/Include
    flags=(--target=aarch64-pc-windows-msvc -Os -ffreestanding -fshort-wchar
      -funsigned-char -fno-stack-protector -mno-outline-atomics
      -mno-implicit-float -mno-stack-arg-probe -Wall -Wextra -Werror
      -I"$headers" -I"$headers/AArch64" -I"$pump/Include" -Iuefi/core)
    clang "''${flags[@]}" -c uefi/components/product-support/Applications/LinuxBoot/LinuxBoot.c -o LinuxBoot.obj
    clang "''${flags[@]}" -c "$pump/Library/PianoProductPumpLib/PianoProductPumpLib.c" -o PumpLib.obj
    clang "''${flags[@]}" -c ${./entry.c} -o Entry.obj
    lld-link /machine:arm64 /subsystem:efi_application /entry:PianoEfiEntry \
      /nodefaultlib /fixed:no /dynamicbase /timestamp:0 \
      /out:LinuxBoot.efi Entry.obj LinuxBoot.obj PumpLib.obj
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 LinuxBoot.efi "$out/EFI/Piano/LinuxBoot.efi"
    mkdir -p "$out/share/licenses/piano-linux-loader"
    cp ${edk2.srcWithVendoring}/License.txt "$out/share/licenses/piano-linux-loader/edk2.txt"
    cp "$pump/Library/PianoProductPumpLib/PianoProductPumpLib.c" \
      "$out/share/licenses/piano-linux-loader/PianoProductPumpLib.c"
    runHook postInstall
  '';

  meta = {
    description = "ARM64 EFI client for SunUEFI's resident Linux loader";
    license = lib.licenses.bsd2Patent;
    platforms = lib.platforms.linux;
  };
}
