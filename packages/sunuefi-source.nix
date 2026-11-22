{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "file:///home/cryolitia/.local/share/xiaomi-piano-nixos/sources/Project-SunUEFI-edcf272063bfaf9be50f69c85961a5bbe1447b7b.tar.gz";
  sha256 = "sha256-i4WMqzahZkRbbL1WkVqjn88B84qQFZfdXPVhgJ1yx8g=";
}
