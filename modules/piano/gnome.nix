{
  config,
  lib,
  ...
}:

let
  powerButtonDatabase = {
    settings."org/gnome/settings-daemon/plugins/power".power-button-action = "suspend";
  };
in
{
  config = lib.mkIf config.services.desktopManager.gnome.enable {
    # Use GNOME's native suspend action in the session and login screen.
    programs.dconf.profiles = {
      user.databases = [ powerButtonDatabase ];
      gdm = lib.mkIf config.services.displayManager.gdm.enable {
        databases = [ powerButtonDatabase ];
      };
    };
  };
}
