{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "file:///home/cryolitia/.local/share/xiaomi-piano-nixos/sources/Project-SunUEFI-2a114b2efce8a257f75195d59fdcdc158cd46a33.tar.gz";
  sha256 = "sha256-PuVvfCC81Xa+neqRi40k2jpJI8b7eo3lAC1RU4SwNeE=";
}
