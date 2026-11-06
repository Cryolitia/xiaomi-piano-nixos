{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/a243df498b0e3103ed3380719888d9c836acf10d.tar.gz";
  sha256 = "sha256-DFlCLcKS7IKXy2R/yekaKlM4n/LEb8qfGTro5ovJFPw=";
}
