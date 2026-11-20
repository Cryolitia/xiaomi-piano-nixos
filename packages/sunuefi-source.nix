{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "file:///home/cryolitia/.local/share/xiaomi-piano-nixos/sources/Project-SunUEFI-91e641e3db69b173d0e11c32f4c8eeb1300c8515.tar.gz";
  sha256 = "sha256-GiWMWmkzrPc4ttx9y9gnIT6YBBVs19FAzFWXEucWt6c=";
}
