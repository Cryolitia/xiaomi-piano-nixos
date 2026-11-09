{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/320de23f0fb0239aa2de5ec9c1532a91c66cfc4b.tar.gz";
  sha256 = "sha256-KzJhdBTmF6p1v43cgnV5mP1bZ881zh21Q4hboUNH90s=";
}
