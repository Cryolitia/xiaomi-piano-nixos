{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/f46280a0e01ebeae40ca2d837a11cd431c2e46b5.tar.gz";
  sha256 = "sha256-lplXazxnH4RJia1HEsdtWQgUFrCilCg0gbZ9LQQCSlA=";
}
