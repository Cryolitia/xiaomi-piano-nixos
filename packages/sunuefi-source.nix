{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/4ea56ada51c45544e010e24055f09649f320bbcc.tar.gz";
  sha256 = "sha256-iG7AknIaau9h44DDHJ5C12saCzyCcWeQx3CN/R0Bn7M=";
}
