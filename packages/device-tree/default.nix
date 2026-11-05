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

    # Keep the builder and local board overlays together in the store.
    # The remaining board overlays follow the pinned SunUEFI policy.
    python3 ${./.}/build.py ${sunuefiSrc} ${panel} \
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
