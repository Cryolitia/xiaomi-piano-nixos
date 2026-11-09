{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
let
  # Reuse the upstream account without importing installer services or root login.
  installationDefaults =
    (import (modulesPath + "/profiles/installation-device.nix") {
      inherit config lib pkgs;
    }).config;
  defaultUser = installationDefaults.services.getty.autologinUser;
in
{
  imports = [ ./diagnostics.nix ];

  # These desktop and login defaults belong to the validation image. Importing
  # the hardware module alone must not change a consumer's users or desktop.
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "piano";
  networking.networkmanager.enable = true;

  time.timeZone = lib.mkDefault "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";
  i18n.supportedLocales = [
    "zh_CN.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # GNOME 50's finger selector can exceed a tablet dialog's height. Reuse
  # Ubuntu's scrollable popover fix until the redesigned UI reaches nixpkgs.
  nixpkgs.overlays = [
    (final: previous: {
      gnome-control-center = previous.gnome-control-center.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (final.fetchurl {
            url = "https://salsa.debian.org/gnome-team/gnome-control-center/-/raw/a84ca92d6fd960500e85b1d4f7840c57378203d6/debian/patches/ubuntu/system-users-Keep-fingerprint-add-print-popover-visible-w.patch";
            hash = "sha256-A2IQ5mF1j045hfVwJtxV1x7bV/9TP7AnwIWURscjCe4=";
          })
        ];
      });
    })
  ];

  services.displayManager.autoLogin = {
    enable = true;
    user = defaultUser;
  };
  services.gnome.gnome-keyring.enable = true;
  services.libinput.enable = true;
  services.power-profiles-daemon.enable = true;
  services.openssh.enable = true;
  # Keep remote diagnostics usable while the fingerprint reader is busy.
  security.pam.services.sshd.fprintAuth = false;

  users.users.${defaultUser} = installationDefaults.users.users.${defaultUser} // {
    # Clear the upstream empty hash so the initial SSH password takes effect.
    initialHashedPassword = null;
    initialPassword = "nixos";
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    chromium
    git
    vim
    usbutils
    pciutils
    fastfetch
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    ibus.engines = with pkgs.ibus-engines; [ libpinyin ];
  };

  programs.dconf.enable = true;
  services.gnome.core-apps.enable = true;

  system.stateVersion = config.system.nixos.release;
}
