{
  lib,
  stdenv,
  callPackage,
  fetchzip,
  runCommand,
  kernelHeaders,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
}:

let
  config = builtins.fromJSON (builtins.readFile "${sunuefiSrc}/config/fingerprint.json");
  firmwareSource = "${sunuefiSrc}/vendor/firmware/hyperos4-fingerprint";
  manifest = builtins.fromJSON (builtins.readFile "${firmwareSource}/manifest.json");
  names = builtins.attrNames manifest.files;
  qcbor = fetchzip {
    url = "${lib.removeSuffix ".git" config.sources.qcbor.url}/archive/${config.sources.qcbor.commit}.tar.gz";
    hash = "sha256-8KWnTqU4oP+WT1OapEGqTMgwHJnms1V1Aj/3WjA3QMY=";
  };

  # The client opens firmware with O_NOFOLLOW. Keep regular, uncompressed
  # files in the store for both the CLI and the libfprint driver.
  firmware = runCommand "piano-goodix-firmware" { } ''
    mkdir -p "$out"
    cd ${firmwareSource}
    sha256sum -c <<'SUMS'
    ${lib.concatMapStringsSep "\n" (name: "${manifest.files.${name}.sha256}  ${name}") names}
    SUMS
    install -m644 ${lib.escapeShellArgs names} "$out/"
  '';
  backend = runCommand "piano-goodix-source" { } ''
    mkdir -p "$out/uapi/linux" "$out/uapi/scsi"
    cp -r ${sunuefiSrc}/linux/userspace/fingerprint/. "$out/"
    cp -r ${qcbor} "$out/qcbor"
    cp ${kernelHeaders}/include/linux/{tee,bsg}.h "$out/uapi/linux/"
    cp ${kernelHeaders}/include/scsi/scsi_bsg_ufs.h "$out/uapi/scsi/"
    grep -q TEE_IOC_OBJECT_INVOKE "$out/uapi/linux/tee.h"
    chmod u+w "$out/piano-goodix.c"
    substituteInPlace "$out/piano-goodix.c" --replace-fail \
      'result = firmware_path_parameter(custom);' \
      'result = open_firmware_at("${firmware}", name);
      if (result != -ENOENT)
        return result;
      result = firmware_path_parameter(custom);'
  '';
in
stdenv.mkDerivation {
  pname = "piano-fingerprint";
  version = "1";
  src = backend;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    "$CC" -O2 -D_GNU_SOURCE -DUSE_QCBOR -isystem uapi -Iqcbor/inc \
      piano-goodix*.c qcbor/src/{UsefulBuf,qcbor_encode,qcbor_decode,qcbor_err_to_str,ieee754}.c \
      -pthread -lm -o piano-fingerprint-ctl

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 piano-fingerprint-ctl "$out/bin/piano-fingerprint-ctl"
    install -Dm644 ${firmwareSource}/manifest.json "$out/share/doc/piano-fingerprint/firmware-manifest.json"
    install -m644 ${firmwareSource}/README.md "$out/share/doc/piano-fingerprint/firmware-source.md"
    install -Dm644 qcbor/LICENSE "$out/share/licenses/piano-fingerprint/QCBOR.txt"
    install -m644 BSD-3-Clause*.txt "$out/share/licenses/piano-fingerprint/"
    install -m644 uapi/linux/tee.h "$out/share/licenses/piano-fingerprint/linux-tee.h"

    runHook postInstall
  '';

  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/piano-fingerprint-ctl" --help
    runHook postInstallCheck
  '';

  passthru = { inherit backend sunuefiSrc; };

  meta = {
    description = "Native Piano Goodix sensor control and QTEE diagnostics";
    license = with lib.licenses; [
      bsd3
      unfree
    ];
    mainProgram = "piano-fingerprint-ctl";
    platforms = [ "aarch64-linux" ];
  };
}
