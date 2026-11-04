{
  lib,
  stdenvNoCC,
  python3,
  dtc,
  callPackage,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
  panel ? "auto",
  boardDtb ? null,
  memoryLayout ? null,
}:

assert builtins.elem panel [
  "auto"
  "boe"
  "csot"
];
stdenvNoCC.mkDerivation {
  pname = "piano-device-tree";
  version = "1";
  dontUnpack = true;
  nativeBuildInputs = [
    python3
    dtc
  ];

  buildPhase = ''
    runHook preBuild

    # The Python builder verifies the base tree and optional RAM profile,
    # then applies the same ordered overlays used by SunUEFI's Linux image.
    python3 ${./build.py} ${sunuefiSrc} ${panel} \
      ${lib.escapeShellArg (if boardDtb == null then "-" else "${boardDtb}")} \
      ${lib.escapeShellArg (if memoryLayout == null then "-" else "${memoryLayout}")}

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p "$out"
    cp piano.dtb manifest.json "$out/"
  '';

  meta = {
    description = "Piano Linux device tree for the existing SunUEFI runtime handoff";
    license = with lib.licenses; [
      gpl2Only
      bsd2
    ];
    platforms = [ "aarch64-linux" ];
  };
}
