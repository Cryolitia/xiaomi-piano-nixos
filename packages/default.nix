{ pkgs }:

let
  kernel = pkgs.callPackage ./kernel { };
in
{
  inherit kernel;
  kernelPackages = pkgs.linuxPackagesFor kernel;
  firmware = pkgs.callPackage ./firmware { };
  fingerprint = pkgs.callPackage ./fingerprint { };
  deviceTree = pkgs.callPackage ./device-tree { };
  bsp = pkgs.callPackage ./bsp { };
  mesa = pkgs.callPackage ./mesa { };
}
