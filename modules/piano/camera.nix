{
  config,
  pianoPackages,
  pkgs,
  ...
}:

let
  camera = pianoPackages.camera;
in
{
  # Use the repaired GStreamer plugin with the distribution's desktop libraries.
  environment.sessionVariables.GST_PLUGIN_PATH_1_0 = [
    "${pianoPackages.pipewire}/lib/gstreamer-1.0"
  ];

  # These virtual devices have no physical alias to trigger module loading.
  # CAMSS, the sensors and their suppliers use ordinary OF deferred probing.
  # The shared daemon and loopback module use the same format handoff.
  boot.extraModulePackages = [
    (config.boot.kernelPackages.v4l2loopback.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ camera.loopbackPatches;
    }))
  ];
  boot.kernelModules = [ "v4l2loopback" ];
  boot.extraModprobeConfig = camera.loopbackOptions;

  environment.systemPackages = [
    camera
    pkgs.v4l-utils
  ];
  services.udev.packages = [ camera ];
  services.pipewire.wireplumber.configPackages = [ camera ];
  users.groups.video = { };

  systemd.services.piano-camerad = {
    description = "Piano camera output";
    wantedBy = [ "multi-user.target" ];
    after = [
      "systemd-modules-load.service"
      "systemd-udev-trigger.service"
    ];
    # Advertise the initialized loopback capture devices before the session
    # starts. Real sensor streaming begins only when an application requests it.
    before = [ "systemd-user-sessions.service" ];
    serviceConfig = {
      Type = "notify";
      NotifyAccess = "main";
      ExecStart = "${camera}/libexec/piano-camerad";
      Group = "video";
      RuntimeDirectory = "piano-camerad";
      RuntimeDirectoryMode = "0750";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
