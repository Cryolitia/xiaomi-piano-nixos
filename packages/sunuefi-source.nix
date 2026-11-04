{ }:

# Kernel policy is read during evaluation, before a target builder is needed.
builtins.fetchTree {
  type = "github";
  owner = "Cryolitia-Forks";
  repo = "Project-SunUEFI";
  rev = "874ef77d11c9616edda656d9fcd135364fb37d32";
  narHash = "sha256-Za0CutJJxm1Oi10v0XS/BwxK4+xKXdmPPMjifFEi1gc=";
}
