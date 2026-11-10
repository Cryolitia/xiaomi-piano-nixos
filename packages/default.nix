{
  pkgs,
  withPen ? false,
}:

let
  kernel = pkgs.callPackage ./kernel { };
  bsp = pkgs.callPackage ./bsp { inherit withPen; };
in
{
  inherit kernel bsp;
  kernelPackages = pkgs.linuxPackagesFor kernel;
  firmware = pkgs.callPackage ./firmware { };
  fingerprint = pkgs.callPackage ./fingerprint { };
  deviceTree = pkgs.callPackage ./device-tree { };
  camera = pkgs.callPackage ./camera { };
  ffmpeg = pkgs.callPackage ./ffmpeg { };
  pipewire = pkgs.callPackage ./pipewire { };
  sensors = pkgs.callPackage ./sensors { };
  mesa = pkgs.callPackage ./mesa { };
}
