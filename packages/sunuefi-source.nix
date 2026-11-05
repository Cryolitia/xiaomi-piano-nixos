{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/3d43d7895bf6400bfded35e2742b7de18f5c63da.tar.gz";
  sha256 = "sha256-s08vm7n5YA72hDYz+q1FRifXNmnSbjX7D7xhJWQaexA=";
}
