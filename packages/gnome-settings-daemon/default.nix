{
  lib,
  gnome-settings-daemon,
  callPackage,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
}:

let
  directory = sunuefiSrc + "/patches/gnome-settings-daemon/${gnome-settings-daemon.version}";
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
