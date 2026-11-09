{
  lib,
  stdenvNoCC,
  python3,
  dtc,
  callPackage,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
  panel ? "auto",
  boardDtb ? null,
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

    # The adapter supplies Nix paths; all board data and transforms follow
    # the pinned SunUEFI source.
    python3 ${./build.py} ${sunuefiSrc} ${panel} \
      ${lib.escapeShellArg (if boardDtb == null then "-" else "${boardDtb}")}

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
