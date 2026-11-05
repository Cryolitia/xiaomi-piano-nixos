{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/414b1671adbf4fe2c08c44ad2decf9aa050b0728.tar.gz";
  sha256 = "sha256-qtldgei7BRSshQigfjh1EDj6R0yf41cYzapKy2uqIoI=";
}
