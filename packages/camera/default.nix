{
  lib,
  stdenv,
  pkg-config,
  libyuv,
  libjpeg,
  callPackage,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
}:

let
  sourceRoot = /. + builtins.unsafeDiscardStringContext (toString sunuefiSrc);
  camera = sourceRoot + "/linux/userspace/camera";
  bsp = sourceRoot + "/linux/bsp";
  pianoQuad = callPackage ./quad.nix { inherit sunuefiSrc; };
  loopbackSeriesPath = "${sunuefiSrc}/patches/v4l2loopback/0.15.4/series.json";
  loopbackSeries = builtins.fromJSON (builtins.readFile loopbackSeriesPath);
  loopbackPatches = map (
    entry:
    let
      path = "${builtins.dirOf loopbackSeriesPath}/${entry.file}";
    in
    assert lib.assertMsg (
      builtins.hashFile "sha256" path == entry.sha256
    ) "Piano loopback patch checksum mismatch: ${entry.file}";
    path
  ) loopbackSeries.patches;
  loopbackOptions = builtins.filter (line: lib.hasPrefix "options v4l2loopback " line) (
    lib.splitString "\n" (builtins.readFile (bsp + "/common/etc/modprobe.d/piano.conf"))
  );
in
assert builtins.length loopbackOptions == 1;
stdenv.mkDerivation {
  pname = "piano-camera";
  version = "1";
  src = lib.fileset.toSource {
    root = sourceRoot;
    fileset = lib.fileset.unions [
      (lib.fileset.difference (lib.fileset.fileFilter (
        file: file.hasExt "c" || file.hasExt "h" || file.name == "Makefile" || file.name == "LICENSE-MIT"
      ) camera) (camera + "/quad"))
      (bsp + "/optional/camera/etc/udev/rules.d/70-piano-camera.rules")
      (bsp + "/optional/camera/etc/wireplumber/wireplumber.conf.d/50-piano-camera.conf")
    ];
  };
  strictDeps = true;
  dontConfigure = true;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    libyuv
    libjpeg
  ];
  makeFlags = [
    "-C"
    "linux/userspace/camera"
    "QUAD_LIB=${lib.getDev pianoQuad}/lib/libpiano_quad.a"
    "QUAD_INCLUDE=${lib.getDev pianoQuad}/include"
  ];
  preBuild = ''
    makeFlagsArray+=("OUT=$PWD/build" "CC=$CC" "CXX=$CXX")
  '';
  installFlags = [ "PREFIX=${placeholder "out"}" ];

  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  checkTarget = "check";

  postInstall = ''
    install -Dm644 linux/bsp/optional/camera/etc/udev/rules.d/70-piano-camera.rules \
      "$out/lib/udev/rules.d/70-piano-camera.rules"
    install -Dm644 linux/bsp/optional/camera/etc/wireplumber/wireplumber.conf.d/50-piano-camera.conf \
      "$out/share/wireplumber/wireplumber.conf.d/50-piano-camera.conf"
    install -Dm644 ${pianoQuad}/share/licenses/piano-quad/LICENSE-MIT \
      "$out/share/licenses/piano-quad/LICENSE-MIT"
    install -Dm644 ${pianoQuad}/share/licenses/demosaic/LICENSE-MIT \
      "$out/share/licenses/demosaic/LICENSE-MIT"
  '';

  passthru = {
    inherit loopbackPatches;
    loopbackOptions = builtins.head loopbackOptions;
  };

  meta = {
    description = "Piano camera output, full-resolution photos and sensor controls";
    license = lib.licenses.mit;
    platforms = [ "aarch64-linux" ];
  };
}
