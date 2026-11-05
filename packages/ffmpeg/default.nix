{
  lib,
  ffmpeg,
  callPackage,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
}:

let
  # Copy only the codec patches, so unrelated shared-source changes do not
  # invalidate this package.
  patchDirectory = builtins.path {
    path = sunuefiSrc + "/linux/bsp/patches/ffmpeg";
    name = "piano-ffmpeg-patches";
  };
  seriesName =
    {
      "7" = "series.json";
      "9" = "series-9.json";
    }
    .${lib.versions.major ffmpeg.version};
  series = builtins.fromJSON (builtins.readFile (patchDirectory + "/${seriesName}"));
  checkedPatch =
    entry:
    let
      path = patchDirectory + "/${entry.path}";
    in
    assert lib.assertMsg (
      builtins.hashFile "sha256" path == entry.sha256
    ) "Piano FFmpeg patch hash mismatch: ${entry.path}";
    path;
in
assert lib.assertMsg (
  ffmpeg.version == series.upstream_version
) "Piano FFmpeg patches require ${series.upstream_version}, but nixpkgs provides ${ffmpeg.version}";
ffmpeg.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ map checkedPatch series.series;
})
