{
  lib,
  stdenvNoCC,
  python3,
  lcms2,
  requireFile,
  fetchurl,
}:

let
  # Generic system-image calibration, shared by all units with the panel.
  # Keep the factory tables outside Git; only the derived ICC files are shipped.
  boe = requireFile {
    name = "p81-42-qdcm.json";
    sha256 = "bbff3f5d19305b25652fbcfc3e34a80ffed7419f0f78320d04026ae7a69f6ec2";
    message = ''
      Read /odm/etc/display/qdcm_calib_data_xiaomi_p81_42_02_0a_vid_mode_dualdsi_dsc_panel.json
      from the Piano OS3.0.304.0.WPYMIXM system image as p81-42-qdcm.json, then run:
        nix-store --add-fixed sha256 p81-42-qdcm.json
    '';
  };
  csot = requireFile {
    name = "p81-35-qdcm.json";
    sha256 = "896d391e826098c1a3edd95d3abd477a25418bbff3c5b575bc608d4ec5ba5c76";
    message = ''
      Read /odm/etc/display/qdcm_calib_data_xiaomi_p81_35_02_0b_vid_mode_dualdsi_dsc_panel.json
      from the Piano OS3.0.304.0.WPYMIXM system image as p81-35-qdcm.json, then run:
        nix-store --add-fixed sha256 p81-35-qdcm.json
    '';
  };
  backlightMap = fetchurl {
    url = "https://raw.githubusercontent.com/MiCode/vendor_opensource_display-drivers/aa06fd1757c28dce96fbe4e04d4530ec21b52aac/msm/mi_disp/mi_backlight_ktz8866.h";
    sha256 = "1ca4ca5e051ded56091a9f6ea1144883bfaf47c2a57b0963397a6c25a4b75207";
  };
in
stdenvNoCC.mkDerivation {
  pname = "piano-display-color";
  version = "1";

  dontUnpack = true;
  dontConfigure = true;
  nativeBuildInputs = [ python3 ];
  SOURCE_DATE_EPOCH = "1";

  buildPhase = ''
    runHook preBuild

    cp ${./generate.py} generate.py
    substituteInPlace generate.py \
      --replace-fail "find_library('lcms2')" "'${lib.getLib lcms2}/lib/liblcms2.so.2'"

    python3 generate.py ${boe} boe.icc \
      --compatible xiaomi,piano-boe-nt36532 --backlight-map ${backlightMap}
    python3 generate.py ${csot} csot.icc \
      --compatible xiaomi,piano-csot-nt36532 --backlight-map ${backlightMap}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 boe.icc "$out/share/color/icc/piano-boe.icc"
    install -Dm644 csot.icc "$out/share/color/icc/piano-csot.icc"

    runHook postInstall
  '';

  # The platform-independent colour assets can be built locally and copied
  # to an ARM builder without transferring the factory source tables.
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = "sha256-6o3B+Sk7n3pARE3n6xgIevl1k7zpSQOBxVxauf7zgd8=";

  meta = {
    description = "Native HDR display profiles for Xiaomi Pad 8 Pro";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
  };
}
