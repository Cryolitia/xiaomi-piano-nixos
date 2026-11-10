{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/da122bad8443f21e0c5a8ecad0a95c4d24ab5b88.tar.gz";
  sha256 = "sha256-dnjNA9EM2EfM2NG7ZGLGSfH+Ck+6EAe+41dMj1erUbI=";
}
