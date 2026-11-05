{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/87cdcd1c3472fef7f6ca014bab531d2c4b06aac7.tar.gz";
  sha256 = "sha256-tXdtRr8O/iveKZJaeeOazvVNZr059AY5sg6PSmqwG+g=";
}
