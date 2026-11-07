{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/cf8530c75c17e1f1982e04eb730ceaebfda405b5.tar.gz";
  sha256 = "sha256-9lSacUbheoy18L0WGd8+jbhkyE6Av8l6Cnzz5jXFlEk=";
}
