{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/ddf8f89ac268842e36c36bf10a9ccd756ee3a56e.tar.gz";
  sha256 = "sha256-xrJyPaDfbxmgzF9ZLgv6mVNXTi2K05DYmEoQwIkh/k4=";
}
