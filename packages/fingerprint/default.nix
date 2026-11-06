{
  lib,
  stdenv,
  callPackage,
  fetchzip,
  writeText,
}:

stdenv.mkDerivation (
  finalAttrs:
  let
    sources =
      (builtins.fromJSON (builtins.readFile "${finalAttrs.src}/config/fingerprint.json")).sources;
    firmware = "${finalAttrs.src}/vendor/firmware/hyperos4-fingerprint";
    manifest = builtins.fromJSON (builtins.readFile "${firmware}/manifest.json");
    firmwareNames = builtins.attrNames manifest.files;
    firmwareChecksums = writeText "piano-fingerprint-firmware-checksums" (
      lib.concatMapStrings (name: "${manifest.files.${name}.sha256}  ${name}\n") firmwareNames
    );

    # Reuse the client's reviewed dependency revisions; keep only Nix content
    # hashes here, alongside the fetch operation that needs them.
    fetchSource =
      name: hash:
      fetchzip {
        url = "${lib.removeSuffix ".git" sources.${name}.url}/archive/${sources.${name}.commit}.tar.gz";
        inherit hash;
      };
    qtee = fetchSource "quic-teec" "sha256-HVtw2RT3LxwcRifzX9XT7nNsWPCJesVbuAhjPSgscus=";
    mink = fetchSource "minkipc" "sha256-mup6oVEMDkT6IlMvSBAsuajLxPa+kVG9HpJmSaP0dio=";
    qcbor = fetchSource "qcbor" "sha256-8KWnTqU4oP+WT1OapEGqTMgwHJnms1V1Aj/3WjA3QMY=";
  in
  {
    pname = "piano-fingerprint";
    version = "1";
    src = callPackage ../sunuefi-source.nix { };
    dontConfigure = true;

    postPatch = ''
      # The native client reads firmware itself. It cannot use the kernel's
      # compressed firmware tree or a distribution-specific /usr directory.
      client=linux/userspace/fingerprint/piano-goodix.c
      substituteInPlace "$client" --replace-fail \
        '/usr/lib/firmware/' "$out/share/piano-fingerprint/firmware/"

      # SET_ACTIVE_GROUP alone does not prove isolation of the TA's FTS paths.
      # The client has no filesystem listener or enrollment/authentication API.
      substituteInPlace "$client" --replace-fail \
        'list queries templates in an isolated Linux user profile.' \
        'list queries TA templates; persistent storage isolation is not implemented.'
    '';

    buildPhase = ''
      runHook preBuild

      # Match SunUEFI's existing client source set. Qualcomm supplies the
      # matching TEE UAPI headers; no Android libraries or HAL are linked.
      "$CC" -O2 -D_GNU_SOURCE -DUSE_QCBOR -Wa,--noexecstack \
        -I${qtee}/libqcomtee/include -I${qtee}/libqcomtee/src \
        -I${mink}/libminkadaptor/include -I${mink}/libminkadaptor/src \
        -I${qcbor}/inc \
        ${qtee}/libqcomtee/src/qcomtee_object.c \
        ${qtee}/libqcomtee/src/objects/credentials_obj.c \
        ${qtee}/libqcomtee/src/objects/mem_obj.c \
        ${mink}/libminkadaptor/src/mink_adaptor.c \
        ${mink}/libminkadaptor/src/supplicant.c \
        ${mink}/libminkadaptor/src/syscall.S \
        ${qcbor}/src/UsefulBuf.c ${qcbor}/src/qcbor_encode.c \
        ${qcbor}/src/qcbor_decode.c ${qcbor}/src/qcbor_err_to_str.c \
        ${qcbor}/src/ieee754.c \
        linux/userspace/fingerprint/piano-goodix.c \
        -pthread -lm -o piano-fingerprint-ctl

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -Dm755 piano-fingerprint-ctl "$out/bin/piano-fingerprint-ctl"
      mkdir -p "$out/share/piano-fingerprint/firmware"
      (
        cd ${firmware}
        sha256sum --check ${firmwareChecksums}
        install -m644 ${lib.escapeShellArgs firmwareNames} "$out/share/piano-fingerprint/firmware/"
        install -Dm644 manifest.json "$out/share/doc/piano-fingerprint/firmware-manifest.json"
        install -m644 README.md "$out/share/doc/piano-fingerprint/firmware-source.md"
      )

      install -Dm644 ${qtee}/${sources.quic-teec.license} "$out/share/licenses/piano-fingerprint/quic-teec.txt"
      install -Dm644 ${mink}/${sources.minkipc.license} "$out/share/licenses/piano-fingerprint/minkipc.txt"
      install -Dm644 ${qcbor}/${sources.qcbor.license} "$out/share/licenses/piano-fingerprint/qcbor.txt"
      install -Dm644 LICENSE.md "$out/share/licenses/piano-fingerprint/Project-SunUEFI.md"

      runHook postInstall
    '';

    # --help exits before opening either TEE or UIO. This is safe on a builder
    # and verifies the actual installed binary, including its runtime linker.
    doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
    installCheckPhase = ''
      runHook preInstallCheck
      "$out/bin/piano-fingerprint-ctl" --help
      runHook postInstallCheck
    '';

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
)
