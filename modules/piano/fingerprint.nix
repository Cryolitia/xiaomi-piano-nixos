{
  lib,
  pianoPackages,
  ...
}:

{
  boot.kernelModules = [
    "qcomtee"
    "uio_piano_fingerprint"
  ];

  # Use fprintd's ordinary enrollment, PolicyKit and PAM integration. The
  # platform driver calls the same native implementation as the diagnostic CLI.
  nixpkgs.overlays = [
    (final: previous: {
      libfprint = final.callPackage ../../packages/fingerprint/libfprint.nix {
        libfprint = previous.libfprint;
        pianoFingerprint = final.callPackage ../../packages/fingerprint { };
      };
    })
  ];
  services.fprintd.enable = true;
  environment.systemPackages = [ pianoPackages.fingerprint ];

  systemd.services.fprintd.serviceConfig = {
    StateDirectory = lib.mkAfter [ "piano-goodix" ];
    StateDirectoryMode = "0700";
    DeviceAllow = [
      "char-uio rw"
      "char-tee rw"
      "char-bsg rw"
    ];
  };
}
