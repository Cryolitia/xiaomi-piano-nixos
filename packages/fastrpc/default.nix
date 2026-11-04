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
  version = "1.0.7";

  src = fetchFromGitHub {
    owner = "qualcomm";
    repo = "fastrpc";
    rev = "228d98b5f143ed917789cde017a8aa548e65b80b";
    hash = "sha256-23aq4o2lRhQdBbdrWBdJKVSjl4JHAqpm/sONeiLBP0c=";
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
