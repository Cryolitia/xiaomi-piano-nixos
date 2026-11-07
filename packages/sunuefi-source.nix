{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/6bc39344b692345678f623ed1749aca1641f1c79.tar.gz";
  sha256 = "sha256-/YmjrssPjSGBTi/LcITieGbuMnaISLOJuJ0B4dvHJ7Y=";
}
