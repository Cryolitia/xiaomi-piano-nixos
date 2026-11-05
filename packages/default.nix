{ pkgs }:

let
  kernel = pkgs.callPackage ./kernel { };
  bsp = pkgs.callPackage ./bsp { };
in
{
  inherit kernel bsp;
  kernelPackages = pkgs.linuxPackagesFor kernel;
  firmware = pkgs.callPackage ./firmware { };
  fingerprint = pkgs.callPackage ./fingerprint { };
  deviceTree = pkgs.callPackage ./device-tree { };
  camera = pkgs.callPackage ./camera {
    inherit (bsp) debianPianoSrc;
  };
  sensors = pkgs.callPackage ./sensors { };
  mesa = pkgs.callPackage ./mesa { };
}
