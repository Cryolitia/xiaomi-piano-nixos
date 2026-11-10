{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/d5bb4462647c301b4ee766ba140d555f136d23bd.tar.gz";
  sha256 = "sha256-v7m8xjnWnykU+8FYK/76y7nDvMCMMO7UHnPoeuLncLQ=";
}
