{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  makeWrapper,
  libyaml,
  libbsd,
}:

stdenv.mkDerivation {
  pname = "fastrpc";
  version = "1.0.8";

  src = fetchFromGitHub {
    owner = "qualcomm";
    repo = "fastrpc";
    rev = "d247519650fe5cb16de6c78edaa95bcc4be25073";
    hash = "sha256-XL0u7zNRxpUHBQ761aXFUupR0AHJfRFRZPa92LNn2ZQ=";
  };

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    makeWrapper
  ];
  buildInputs = [
    libyaml
    libbsd
  ];

  configureFlags = [
    "--sbindir=${placeholder "out"}/bin"
    "--with-systemdsystemunitdir=${placeholder "out"}/lib/systemd/system"
    "--with-udevrulesdir=${placeholder "out"}/lib/udev/rules.d"
    "--with-sysusersdir=${placeholder "out"}/lib/sysusers.d"
    "--with-config-base-dir=${placeholder "out"}/share/qcom/"
  ];

  postInstall = ''
    install -Dm644 LICENSE.txt "$out/share/licenses/fastrpc/LICENSE.txt"
  '';

  # adsprpcd loads its listener with dlopen, so it has no ELF dependency
  # through which Nix could discover the listener's library directory.
  postFixup = ''
    wrapProgram "$out/bin/adsprpcd" --prefix LD_LIBRARY_PATH : "$out/lib"
  '';

  meta = {
    description = "Qualcomm FastRPC userspace and DSP listener";
    homepage = "https://github.com/qualcomm/fastrpc";
    license = lib.licenses.bsd3;
    platforms = [ "aarch64-linux" ];
  };
}
