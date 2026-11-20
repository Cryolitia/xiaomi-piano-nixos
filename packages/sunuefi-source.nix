{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "file:///home/cryolitia/.local/share/xiaomi-piano-nixos/sources/Project-SunUEFI-901b236cd77243985a06f9f2bf1aae16ad1224ac.tar.gz";
  sha256 = "sha256-ANKK+2pzXaU69Y9CTE9y0dLbbT1dCcZ4bfNWDpqH2PY=";
}
