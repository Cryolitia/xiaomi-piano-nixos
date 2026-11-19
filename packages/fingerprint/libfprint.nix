{
  lib,
  libfprint,
  pianoFingerprint,
}:

let
  directory = "${pianoFingerprint.sunuefiSrc}/patches/libfprint/${lib.getVersion libfprint}";
  series = builtins.fromJSON (builtins.readFile "${directory}/series.json");
in
libfprint.overrideAttrs (old: {
  patches =
    (old.patches or [ ])
    ++ map (
      entry:
      let
        patch = "${directory}/${entry.file}";
      in
      assert lib.assertMsg (
        builtins.hashFile "sha256" patch == entry.sha256
      ) "Piano libfprint patch checksum differs: ${entry.file}";
      patch
    ) series.patches;

  postPatch = (old.postPatch or "") + ''
    backend=libfprint/drivers/piano-goodix
    mkdir -p "$backend"
    cp -r ${pianoFingerprint.backend}/. "$backend/"
  '';
})
