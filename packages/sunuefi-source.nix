{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/39d52416dcc18fe86bc865458376c8e93d650230.tar.gz";
  sha256 = "sha256-QNKhIFigJOSUf7rXc2toXS6UOaVJFY3JRd0iKcGVI/E=";
}
