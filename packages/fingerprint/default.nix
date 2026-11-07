{
  lib,
  stdenv,
  callPackage,
  fetchzip,
  writeText,
  applyPatches,
  linuxHeaders,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
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
    minkSeriesPath = "${finalAttrs.src}/${sources.minkipc.patch_series}";
    minkSeries = builtins.fromJSON (builtins.readFile minkSeriesPath);
    mink = applyPatches {
      name = "piano-fingerprint-minkipc";
      src = fetchSource "minkipc" "sha256-mup6oVEMDkT6IlMvSBAsuajLxPa+kVG9HpJmSaP0dio=";
      patches = map (
        entry:
        let
          path = "${builtins.dirOf minkSeriesPath}/${entry.file}";
        in
        assert lib.assertMsg (
          builtins.hashFile "sha256" path == entry.sha256
        ) "Piano MinkIPC patch hash mismatch: ${entry.file}";
        path
      ) minkSeries.patches;
    };
    qcbor = fetchSource "qcbor" "sha256-8KWnTqU4oP+WT1OapEGqTMgwHJnms1V1Aj/3WjA3QMY=";
  in
  {
    pname = "piano-fingerprint";
    version = "1";
    outputs = [
      "out"
      "dev"
    ];
    src = sunuefiSrc;
    dontConfigure = true;
    buildInputs = [ linuxHeaders ];

    postPatch = ''
      # The native client reads firmware itself. It cannot use the kernel's
      # compressed firmware tree or a distribution-specific /usr directory.
      client=linux/userspace/fingerprint/piano-goodix.c
      substituteInPlace "$client" --replace-fail \
        '/usr/lib/firmware/' "$out/share/piano-fingerprint/firmware/"
    '';

    buildPhase = ''
      runHook preBuild

      # Match SunUEFI's existing client source set. Qualcomm supplies the
      # matching TEE UAPI headers; no Android libraries or HAL are linked.
      includes=(
        -I${qtee}/libqcomtee/include -I${qtee}/libqcomtee/src
        -I${mink}/libminkadaptor/include -I${mink}/libminkadaptor/src
        -I${mink}/listeners/libfsservice/gpfs
        -I${mink}/listeners/libfsservice/fs -I${mink}/listeners/libfsservice/cmn
        -I${qcbor}/inc -Ilinux/userspace/fingerprint
      )
      sources=(
        ${qtee}/libqcomtee/src/qcomtee_object.c
        ${qtee}/libqcomtee/src/objects/credentials_obj.c
        ${qtee}/libqcomtee/src/objects/mem_obj.c
        ${mink}/libminkadaptor/src/mink_adaptor.c
        ${mink}/libminkadaptor/src/supplicant.c
        ${mink}/libminkadaptor/src/syscall.S
        ${qcbor}/src/UsefulBuf.c ${qcbor}/src/qcbor_encode.c
        ${qcbor}/src/qcbor_decode.c ${qcbor}/src/qcbor_err_to_str.c
        ${qcbor}/src/ieee754.c
        linux/userspace/fingerprint/piano-goodix-storage.c
        linux/userspace/fingerprint/piano-goodix-events.c
        linux/userspace/fingerprint/piano-goodix-gatekeeper.c
        linux/userspace/fingerprint/piano-goodix-operations.c
        linux/userspace/fingerprint/piano-goodix-rpmb.c
        linux/userspace/fingerprint/piano-goodix.c
      )
      mkdir objects
      for source in "''${sources[@]}"; do
        "$CC" -O2 -fPIC -D_GNU_SOURCE -DUSE_QCBOR -Wa,--noexecstack \
          "''${includes[@]}" -c "$source" -o "objects/''${source##*/}.o"
      done
      "$AR" rcs libpiano-goodix.a objects/*.o
      "$CC" -O2 "''${includes[@]}" \
        linux/userspace/fingerprint/piano-goodix-cli.c \
        libpiano-goodix.a -pthread -lm -o piano-fingerprint-ctl

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -Dm755 piano-fingerprint-ctl "$out/bin/piano-fingerprint-ctl"
      install -Dm644 libpiano-goodix.a "$dev/lib/libpiano-goodix.a"
      install -Dm644 linux/userspace/fingerprint/piano-goodix.h "$dev/include/piano-goodix.h"
      mkdir -p "$dev/lib/pkgconfig"
      cat > "$dev/lib/pkgconfig/piano-goodix.pc" <<EOF
      prefix=$dev
      libdir=$dev/lib
      includedir=$dev/include
      Name: piano-goodix
      Description: Native Piano Goodix enrollment and authentication
      Version: ${finalAttrs.version}
      Libs: -L$dev/lib -lpiano-goodix -pthread -lm
      Cflags: -I$dev/include
      EOF
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
