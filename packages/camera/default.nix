{
  lib,
  stdenv,
  python3,
  patch,
  callPackage,
  debianPianoSrc,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
}:

let
  bsp = sunuefiSrc + "/linux/bsp";
  loopbackOptions = builtins.filter (line: lib.hasPrefix "options v4l2loopback " line) (
    lib.splitString "\n" (builtins.readFile (bsp + "/common/etc/modprobe.d/piano.conf"))
  );
in
assert builtins.length loopbackOptions == 1;
stdenv.mkDerivation {
  pname = "piano-camera";
  version = "1";
  src = sunuefiSrc;
  strictDeps = true;
  dontConfigure = true;

  nativeBuildInputs = [
    python3
    patch
  ];

  buildPhase = ''
    runHook preBuild

    python3 ${./prepare.py} ${debianPianoSrc}

    $CC -O2 -Wall -Wextra -Dmain=PianoOriginalMain \
      -c piano-camerad.c -o piano-camerad.o
    $CC piano-camerad-entry.c piano-camerad.o -lm -o piano-camerad
    $CC -O2 -Wall -Wextra -Dmain=PianoOriginalMain \
      -c linux/userspace/piano-camera-ctl.c -o piano-camera-ctl.o
    $CC piano-camera-ctl-entry.c piano-camera-ctl.o -o piano-camera-ctl

    runHook postBuild
  '';

  # The shared main wrappers handle --help before any device access.
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  checkPhase = ''
    runHook preCheck
    ./piano-camerad --help
    ./piano-camera-ctl --help
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 piano-camerad "$out/libexec/piano-camerad"
    install -Dm755 piano-camera-ctl "$out/bin/piano-camera-ctl"
    install -Dm644 ${bsp}/optional/camera/etc/udev/rules.d/70-piano-camera.rules \
      "$out/lib/udev/rules.d/70-piano-camera.rules"
    install -Dm644 ${bsp}/optional/camera/etc/wireplumber/wireplumber.conf.d/50-piano-camera.conf \
      "$out/share/wireplumber/wireplumber.conf.d/50-piano-camera.conf"

    runHook postInstall
  '';

  passthru.loopbackOptions = builtins.head loopbackOptions;

  meta = {
    description = "Piano hardware ISP camera output and sensor controls";
    license = lib.licenses.mit;
    platforms = [ "aarch64-linux" ];
  };
}
