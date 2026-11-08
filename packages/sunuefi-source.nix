{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/e50edc3d9e9fb1e50f8643b98e0da135d50b54d4.tar.gz";
  sha256 = "sha256-sdDjTlOyLvfQn3ZUr3gyR+Lqebp0NK29/aGUkBFYWKI=";
}
