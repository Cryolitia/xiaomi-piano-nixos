{
  lib,
  sunuefiSrc,
  package,
  component,
  seriesVersion ? package.version,
  exclude ? [ ],
}:

let
  directory = "${sunuefiSrc}/patches/${component}/${seriesVersion}";
  series = builtins.fromJSON (builtins.readFile "${directory}/series.json");
  checkedPatch =
    entry:
    let
      path = "${directory}/${entry.file}";
    in
    assert lib.assertMsg (
      builtins.hashFile "sha256" path == entry.sha256
    ) "SunUEFI ${component} patch checksum differs: ${entry.file}";
    builtins.path {
      inherit path;
      name = builtins.baseNameOf entry.file;
    };
in
assert lib.assertMsg (builtins.elem package.version (
  series.versions or [ series.version ]
)) "SunUEFI ${component} patch series ${seriesVersion} does not support ${package.version}";
package.overrideAttrs (old: {
  patches =
    (old.patches or [ ])
    ++ map checkedPatch (
      builtins.filter (entry: !(builtins.elem (builtins.baseNameOf entry.file) exclude)) series.patches
    );
})
