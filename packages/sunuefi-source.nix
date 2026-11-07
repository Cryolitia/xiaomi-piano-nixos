{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/dd7735c07cb5736f9810075535387c25d6a1e2d8.tar.gz";
  sha256 = "sha256-QxRj4wGPKmgeZ8HVBvD9hTxw5USKS3tTp/2eapBxeVk=";
}
