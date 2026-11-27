{
  pkgs,
  sunuefiSrc,
  withPen ? false,
}:

let
  kernel = pkgs.callPackage ./kernel { inherit sunuefiSrc; };
  bsp = pkgs.callPackage ./bsp { inherit sunuefiSrc withPen; };
  kernelHeaders = pkgs.linuxHeaders.overrideAttrs (_: {
    inherit (kernel) src version;
  });
in
{
  inherit kernel bsp;
  kernelPackages = pkgs.linuxPackagesFor kernel;
  firmware = pkgs.callPackage ./firmware { inherit sunuefiSrc; };
  fingerprint = pkgs.callPackage ./fingerprint { inherit kernelHeaders sunuefiSrc; };
  deviceTree = pkgs.callPackage ./device-tree {
    inherit sunuefiSrc;
    kernelSource = kernel.src;
  };
  camera = pkgs.callPackage ./camera { inherit sunuefiSrc; };
  qcom-va-driver = pkgs.callPackage ./qcom-va-driver { };
  sensors = pkgs.callPackage ./sensors { inherit sunuefiSrc; };
  mesa = pkgs.callPackage ./mesa { inherit sunuefiSrc; };
}
