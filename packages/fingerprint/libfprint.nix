{
  lib,
  libfprint,
  pianoFingerprint,
}:

let
  patched = import ../sunuefi-patches.nix {
    inherit lib;
    sunuefiSrc = pianoFingerprint.sunuefiSrc;
    package = libfprint;
    component = "libfprint";
  };
in
patched.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    backend=libfprint/drivers/piano-goodix
    mkdir -p "$backend"
    cp -r ${pianoFingerprint.backend}/. "$backend/"
  '';
})
