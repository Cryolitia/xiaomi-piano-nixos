{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/74baf0043074d61701f4d48138add23df7718f50.tar.gz";
  sha256 = "sha256-dnjNA9EM2EfM2NG7ZGLGSfH+Ck+6EAe+41dMj1erUbI=";
}
