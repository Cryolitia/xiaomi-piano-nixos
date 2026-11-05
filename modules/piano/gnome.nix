{
  config,
  lib,
  ...
}:

let
  powerButtonDatabase = {
    settings."org/gnome/settings-daemon/plugins/power".power-button-action = "lock-screen";
  };
in
{
  config = lib.mkIf config.services.desktopManager.gnome.enable {
    # Keep locking and display power in the existing GNOME daemons. Shell
    # records the press-time state before idle handling can wake the display.
    nixpkgs.overlays = [ (import ../../packages/gnome) ];

    # Defaults remain editable in Settings. Apply the same physical-key
    # behavior to the greeter when GDM is the selected display manager.
    programs.dconf.profiles = {
      user.databases = [ powerButtonDatabase ];
      gdm = lib.mkIf config.services.displayManager.gdm.enable {
        databases = [ powerButtonDatabase ];
      };
    };
  };
}
