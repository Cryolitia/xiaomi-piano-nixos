{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/375b4b8d6fe7bd224e01f797dd93ee983aa887d3.tar.gz";
  sha256 = "sha256-jx3pilkZRiVDHuvlGnOAtnclTVyyKN9xNIgDJjyIrn4=";
}
