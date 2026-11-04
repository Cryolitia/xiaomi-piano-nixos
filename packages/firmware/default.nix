{
  lib,
  stdenvNoCC,
  python3,
  callPackage,
  fetchFromGitHub,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
}:

stdenvNoCC.mkDerivation {
  pname = "piano-firmware";
  version = "1";
  src = fetchFromGitHub {
    name = "source";
    owner = "blu-sharky";
    repo = "piano-firmware";
    rev = "05fc37c09ca8146eecfc4920f8485479db140ae5";
    hash = "sha256-BoKWcBkNaE0wDTYjLNpp35f7gv1YJHURcFptdIhLefo=";
  };
  dontBuild = true;
  nativeBuildInputs = [ python3 ];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/firmware" "$out/share/doc/piano-firmware"
    cd firmware
    sha256sum -c SHA256SUMS
    cp -r . "$out/lib/firmware/"
    chmod -R u+w "$out"
    cp -r ../LICENSES "$out/share/doc/piano-firmware/"
    cp ../README.md "$out/share/doc/piano-firmware/README.source.md"
    python3 ${./install-overlays.py} ${sunuefiSrc} "$out"
    rm "$out/lib/firmware/SHA256SUMS"
    runHook postInstall
  '';
  meta = {
    description = "Pinned Xiaomi Piano device firmware with matching HyperOS 4 DSP protocol";
    # The source contains proprietary Qualcomm/Xiaomi binaries. The upstream
    # notices do not grant a general redistribution license.
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
