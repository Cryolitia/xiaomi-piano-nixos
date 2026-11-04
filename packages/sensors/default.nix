{
  lib,
  stdenv,
  callPackage,
  fetchFromGitHub,
  applyPatches,
  makeWrapper,
  python3,
  bash,
  coreutils,
  gawk,
  kmod,
  lvm2,
  util-linux,
  erofs-utils,
  libssc,
  iio-sensor-proxy,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
}:

let
  policy = (builtins.fromJSON (builtins.readFile (sunuefiSrc + "/config/release.json"))).sensors;
  source = applyPatches {
    name = "piano-sensors-source";
    src = fetchFromGitHub {
      owner = "blu-sharky";
      repo = "piano-sensors";
      rev = policy.commit;
      hash = "sha256-XW83OBYKBfIHKGwGkQ5umzeVC1q04qnVEsfXOgtCm3Q=";
    };
    patches = map (path: sunuefiSrc + "/${path}") policy.patches;
  };

  ssc = libssc.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      "${source}/patches/libssc/0001-fix-sensor-property-types.patch"
    ];
  });
  sensorProxy = (iio-sensor-proxy.override { libssc = ssc; }).overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      "${source}/patches/iio-sensor-proxy/ssc-claim-race.patch"
    ];
  });
  runtimePython = python3.withPackages (ps: [ ps.liblp ]);

  runtime = stdenv.mkDerivation {
    pname = "piano-sensors";
    version = "5";
    src = source;
    nativeBuildInputs = [ makeWrapper ];
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/libexec/piano-sensors" "$out/lib/udev/rules.d"
      cp piano-sensors/piano-sensors-import "$out/libexec/piano-sensors/import"
      cp piano-sensors/piano-sensors-wait "$out/bin/piano-sensors-wait"
      cp piano-sensors/debian/piano-sensors.udev "$out/lib/udev/rules.d/81-piano-sensors.rules"

      # Reuse the importer and its read-only mappings; choose the active GPT
      # slot and validate liblp metadata before supplying a linear table.
      substituteInPlace "$out/libexec/piano-sensors/import" \
        --replace-fail '#!/bin/sh' '#!${bash}/bin/sh' \
        --replace-fail '/usr/libexec/piano-sensors/piano-sensors-lp-table' "$out/bin/piano-sensors-lp-table" \
        --replace-fail '/run/piano-sensors-persist.XXXXXX' '/run/piano-sensors/persist.XXXXXX'
      substituteInPlace "$out/bin/piano-sensors-wait" \
        --replace-fail '#!/bin/sh' '#!${bash}/bin/sh'

      makeWrapper ${runtimePython}/bin/python3 "$out/bin/piano-sensors-import" \
        --add-flags '${./partitions.py} import' \
        --add-flags "--importer=$out/libexec/piano-sensors/import"
      makeWrapper ${runtimePython}/bin/python3 "$out/bin/piano-sensors-lp-table" \
        --add-flags '${./partitions.py} table'

      for program in "$out/bin/"* "$out/libexec/piano-sensors/import"; do
        wrapProgram "$program" --prefix PATH : ${
          lib.makeBinPath [
            coreutils
            gawk
            kmod
            lvm2
            util-linux
            erofs-utils
            ssc
          ]
        }
      done

      install -Dm644 piano-sensors/debian/copyright "$out/share/licenses/piano-sensors/copyright"

      runHook postInstall
    '';

    meta = {
      description = "Piano SSC configuration import and sensor readiness";
      homepage = "https://github.com/blu-sharky/piano-sensors";
      license = lib.licenses.mit;
      platforms = [ "aarch64-linux" ];
    };
  };
in
{
  inherit runtime sensorProxy;
  libssc = ssc;
  fastrpc = callPackage ../fastrpc { };
}
