{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/ce0f10d8d8b45c32907551a1137882fa25dcc398.tar.gz";
  sha256 = "sha256-7bvX959kzMe/kC+u4sM8XCofRuz/4+paPRfujOVCSWc=";
}
