{
  lib,
  ffmpeg,
  callPackage,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
}:

let
  seriesFile =
    {
      "7" = "linux/bsp/patches/ffmpeg/series.json";
      "9" = "patches/ffmpeg/9.0.2/series.json";
    }
    .${lib.versions.major ffmpeg.version};
  seriesPath = sunuefiSrc + "/${seriesFile}";
  series = builtins.fromJSON (builtins.readFile seriesPath);

  # Resolve entries beside their manifest, including shared older patches.
  # Import each patch separately so unrelated source changes do not rebuild FFmpeg.
  checkedPatch =
    entry:
    let
      path = builtins.dirOf seriesPath + "/${entry.path}";
    in
    assert lib.assertMsg (
      builtins.hashFile "sha256" path == entry.sha256
    ) "Piano FFmpeg patch hash mismatch: ${entry.path}";
    builtins.path {
      inherit path;
      name = builtins.baseNameOf entry.path;
    };
in
assert lib.assertMsg (
  ffmpeg.version == series.upstream_version
) "Piano FFmpeg patches require ${series.upstream_version}, but nixpkgs provides ${ffmpeg.version}";
ffmpeg.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ map checkedPatch series.series;
})
