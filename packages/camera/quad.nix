{
  lib,
  rustPlatform,
  stdenv,
  fetchCrate,
  applyPatches,
  callPackage,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
}:

let
  sourceRoot = /. + builtins.unsafeDiscardStringContext (toString sunuefiSrc);
  quad = sourceRoot + "/linux/userspace/camera/quad";
  cargo = builtins.fromTOML (builtins.readFile (quad + "/Cargo.toml"));
  seriesPath = sourceRoot + "/patches/demosaic/0.3.0/series.json";
  series = builtins.fromJSON (builtins.readFile seriesPath);
  src = lib.fileset.toSource {
    root = quad;
    fileset = lib.fileset.unions [
      (quad + "/Cargo.toml")
      (quad + "/Cargo.lock")
      (quad + "/src")
      (quad + "/include")
      (quad + "/tests")
      (quad + "/LICENSE-MIT")
    ];
  };
  demosaic = applyPatches {
    name = "${series.source.pname}-${series.source.version}-patched";
    src = fetchCrate {
      inherit (series.source) pname version sha256;
      # The shared hash checks the archive, not an unpacked fetchzip tree.
      unpack = false;
    };
    patches = map (
      entry:
      let
        path = builtins.dirOf seriesPath + "/${entry.file}";
      in
      assert lib.assertMsg (
        builtins.hashFile "sha256" path == entry.sha256
      ) "Piano Quad CFA patch hash mismatch: ${entry.file}";
      builtins.path {
        inherit path;
        name = entry.file;
      }
    ) series.patches;
  };
in
rustPlatform.buildRustPackage {
  pname = cargo.package.name;
  version = cargo.package.version;
  inherit src;
  outputs = [
    "out"
    "dev"
  ];

  # The only dependency is an ordinary local path. Its original archive and
  # reviewed patch are checked above; Cargo's lock and registry checks stay on.
  cargoLock.lockFile = src + "/Cargo.lock";
  postPatch = ''
    mkdir -p vendor
    ln -s ${demosaic} vendor/demosaic
  '';
  cargoBuildFlags = [
    "--locked"
    "--lib"
  ];
  cargoTestFlags = [
    "--locked"
    "--lib"
    "--tests"
  ];
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  postCheck = ''
    $CC -std=c17 -O2 -Wall -Wextra -Werror -Iinclude tests/c-api.c \
      target/${stdenv.hostPlatform.rust.rustcTarget}/release/libpiano_quad.a \
      -pthread -ldl -lm -o c-api
    ./c-api
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 target/${stdenv.hostPlatform.rust.rustcTarget}/release/libpiano_quad.a \
      "$dev/lib/libpiano_quad.a"
    install -Dm644 include/piano-quad.h "$dev/include/piano-quad.h"
    install -Dm644 LICENSE-MIT "$out/share/licenses/piano-quad/LICENSE-MIT"
    install -Dm644 vendor/demosaic/LICENSE-MIT "$out/share/licenses/demosaic/LICENSE-MIT"

    runHook postInstall
  '';

  meta = {
    description = "Full-resolution Quad CFA RAW10 conversion";
    license = lib.licenses.mit;
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
