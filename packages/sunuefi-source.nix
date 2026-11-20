{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "https://codeload.github.com/slwyts/Project-SunUEFI/tar.gz/4e3a010961a470e64f4d12f0a7d8ffc217fb7b36";
  sha256 = "sha256-HOfvKLcBWPYnkB5EzoxPXwaP5XB5bqma+E4OIL2rjcM=";
}
