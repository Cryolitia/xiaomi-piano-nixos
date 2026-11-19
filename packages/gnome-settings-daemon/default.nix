{
  lib,
  gnome-settings-daemon,
  sunuefiSrc,
}:

import ../sunuefi-patches.nix {
  inherit lib sunuefiSrc;
  package = gnome-settings-daemon;
  component = "gnome-settings-daemon";
  seriesVersion = "51.0";
}
