{
  config,
  lib,
  pianoPackages,
  ...
}:

let
  powerDatabase = {
    settings."org/gnome/settings-daemon/plugins/power" = {
      power-button-action = "suspend";
      sleep-inactive-ac-type = "nothing";
      sleep-inactive-battery-type = "suspend";
    };
  };
in
{
  config = lib.mkIf config.services.desktopManager.gnome.enable {
    # The internal panel consumes calibrated RGB rather than a PQ wire signal.
    # Mutter selects its factory ICC from the panel's OF compatible string.
    nixpkgs.overlays = [
      (final: previous: {
        mutter = final.callPackage ../../packages/mutter {
          mutter = previous.mutter;
        };
      })
    ];
    environment.systemPackages = [ pianoPackages.displayColor ];
    environment.pathsToLink = [ "/share/color/icc" ];

    # Keep screen blanking and locking on AC; suspend automatically on battery.
    programs.dconf.profiles = {
      user.databases = [ powerDatabase ];
      gdm = lib.mkIf config.services.displayManager.gdm.enable {
        databases = [ powerDatabase ];
      };
    };

    services.logind.settings.Login = {
      HandleLidSwitch = lib.mkDefault "suspend";
      HandleLidSwitchExternalPower = lib.mkDefault "lock";
    };

    # Explicit suspend requests, including the native power key, still use deep.
    systemd.sleep.settings.Sleep.MemorySleepMode = lib.mkDefault "deep";
  };
}
