{ }:

# Kernel policy is read during evaluation, before a target builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/a460e6e3b50c7ee3008e970e22721028008772bc.tar.gz";
  sha256 = "sha256-0n/eq+0mmIn+TQajfDDYgmvXbkoXDQRwwsINrIiaWss=";
}
