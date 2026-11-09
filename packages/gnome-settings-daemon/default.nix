{
  lib,
  gnome-settings-daemon,
  callPackage,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
}:

let
  # 51.0 keeps the power API patched by the 50.1 series.
  seriesVersion =
    {
      "51.0" = "50.1";
    }
    .${gnome-settings-daemon.version} or gnome-settings-daemon.version;
  directory = sunuefiSrc + "/patches/gnome-settings-daemon/${seriesVersion}";
  series = builtins.fromJSON (builtins.readFile (directory + "/series.json"));
  checkedPatch =
    entry:
    let
      path = directory + "/${entry.file}";
    in
    assert lib.assertMsg (
      builtins.hashFile "sha256" path == entry.sha256
    ) "GNOME Settings Daemon patch checksum differs: ${entry.file}";
    builtins.path {
      inherit path;
      name = entry.file;
    };
in
gnome-settings-daemon.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ map checkedPatch series.patches;
})
