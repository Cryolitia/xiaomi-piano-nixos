{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/4044f99feec58671438499d4f49dae649981f47d.tar.gz";
  sha256 = "sha256-wLHHObAYVL6rXtWUjxwVp2c/M26jPQx2xPKbZjxrCqo=";
}
