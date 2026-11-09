{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/84630f60275a93d422aacdc251876cff244e617f.tar.gz";
  sha256 = "sha256-a3aQxnFXFmXxl8UQQ76X0ITwpNGEL2WID0njg2sLo1Q=";
}
