{
  config,
  lib,
  pkgs,
  pianoPackages,
  ...
}:

let
  ucm = pkgs.alsa-ucm-conf.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      cp -a ${pianoPackages.bsp}/share/alsa/ucm2/. "$out/share/alsa/ucm2/"
    '';
  });
  ucmPath = "${ucm}/share/alsa/ucm2";
  stereo = {
    "channelmix.upmix" = true;
    "channelmix.upmix-method" = "simple";
    "channelmix.normalize" = false;
    "channelmix.rear-delay" = 0;
  };
in
{
  # This extends the standard UCM tree instead of hiding its common includes.
  environment.sessionVariables.ALSA_CONFIG_UCM2 = ucmPath;
  services.pipewire.extraConfig = {
    client."60-piano-audio"."stream.properties" = stereo;
    pipewire-pulse."60-piano-audio"."stream.properties" = stereo;
  };
  services.pipewire.wireplumber.extraConfig."50-piano-audio"."monitor.alsa.rules" = [
    {
      matches = [ { "node.name" = "alsa_output.platform-soc_sound-ml.HiFi__Speaker__sink"; } ];
      actions.update-props = {
        "node.description" = "内置扬声器";
        "node.nick" = "内置扬声器";
      };
    }
    {
      matches = [ { "node.name" = "alsa_input.platform-soc_sound-ml.HiFi__Mic__source"; } ];
      actions.update-props = {
        "node.description" = "内置麦克风";
        "node.nick" = "内置麦克风";
        "audio.position" = [ "MONO" ];
      };
    }
  ];
  systemd.user.services = lib.mkIf config.services.pipewire.enable {
    pipewire.environment.ALSA_CONFIG_UCM2 = ucmPath;
    wireplumber = lib.mkIf config.services.pipewire.wireplumber.enable {
      environment.ALSA_CONFIG_UCM2 = ucmPath;
    };
  };
}
