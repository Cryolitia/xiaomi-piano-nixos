{
  lib,
  pipewire,
  sunuefiSrc,
}:

import ../sunuefi-patches.nix {
  inherit lib sunuefiSrc;
  package = pipewire;
  component = "pipewire";
}
