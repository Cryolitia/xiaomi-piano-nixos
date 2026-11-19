{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://github.com/Cryolitia-Forks/Project-SunUEFI/archive/3ce615da985fb33e5a3192bef46b7bfcdd13e75e.tar.gz";
  sha256 = "sha256-X69InVd7rUTJ+qiA7Yn4SDi+uJhTj5So0qdsnfmGzxk=";
}
