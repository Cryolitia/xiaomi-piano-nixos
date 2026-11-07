{
  lib,
  libfprint,
  pianoFingerprint,
}:

let
  directory = "${pianoFingerprint.src}/patches/libfprint/${lib.getVersion libfprint}";
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

  # Meson enables the platform driver when its native transport is present.
  # Keep the existing USB drivers and the upstream test drivers available.
  buildInputs = (old.buildInputs or [ ]) ++ [ (lib.getDev pianoFingerprint) ];
})
