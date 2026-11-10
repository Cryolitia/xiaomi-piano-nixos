{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/0ace19501a611f0648add57af9940d1d1db18edd.tar.gz";
  sha256 = "sha256-GuU6zlw5KfIrGmy2f1EtGSQ83uDbaG1NTDROiHP41X8=";
}
