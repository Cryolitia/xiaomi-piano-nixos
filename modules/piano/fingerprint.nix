{ pianoPackages, ... }:

{
  # Platform autoloading is restricted by boot.nix. Register the existing
  # control interfaces explicitly; sensor power remains off until opened.
  boot.kernelModules = [
    "qcomtee"
    "uio_piano_fingerprint"
  ];

  # This client provides the implemented sensor and QTEE operations. Desktop
  # authentication belongs to a future libfprint driver, not a boot service.
  environment.systemPackages = [ pianoPackages.fingerprint ];
}
