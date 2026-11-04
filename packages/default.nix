{
  pkgs,
  sunuefiSrc,
  linuxSrc,
  firmwareSrc,
  debianPianoSrc,
  mesaPatchesSrc,
  audioReachSrc,
}:

let
  kernel = pkgs.callPackage ./kernel { inherit sunuefiSrc linuxSrc; };
in
{
  inherit kernel;
  kernelPackages = pkgs.linuxPackagesFor kernel;
  firmware = pkgs.callPackage ./firmware { inherit sunuefiSrc firmwareSrc; };
  deviceTree = pkgs.callPackage ./device-tree { inherit sunuefiSrc; };
  bsp = pkgs.callPackage ./bsp { inherit sunuefiSrc debianPianoSrc audioReachSrc; };
  linuxLoader = pkgs.callPackage ./linux-loader { inherit sunuefiSrc; };
  mesa = pkgs.callPackage ./mesa { inherit mesaPatchesSrc; };
}
