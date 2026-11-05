final: prev: {
  mutter = prev.mutter.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./mutter-display-power.patch ];
  });
  gnome-shell = prev.gnome-shell.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./shell-power-button.patch ];
  });
  gnome-settings-daemon = prev.gnome-settings-daemon.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./settings-daemon-power-button.patch ];
  });
  gnome-control-center = prev.gnome-control-center.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./control-center-power-button.patch ];
  });
}
