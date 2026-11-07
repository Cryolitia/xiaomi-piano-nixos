{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/3986dc1659ec7c7757c5e9790e2be4f304c149e9.tar.gz";
  sha256 = "sha256-x0zcluDNvLE/Img/32gb7t2R9de19bD6bQxb8S/c4vk=";
}
