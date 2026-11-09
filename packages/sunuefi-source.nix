{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/6a8c2ae5d2bd3d5216ed38a20d3a75d3d09f5035.tar.gz";
  sha256 = "sha256-rZTSH5btb3FQrEhE9kq2cHFw9dq/pbLbTu26PwCaxMw=";
}
