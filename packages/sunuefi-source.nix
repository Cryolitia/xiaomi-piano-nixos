{ }:
# Shared hardware policy is read during evaluation, before a builder is needed.
builtins.fetchTarball {
  url = "file:///home/cryolitia/.local/share/xiaomi-piano-nixos/sources/Project-SunUEFI-398bbb79f26b39b391830729339819cac6e01ff2.tar.gz";
  sha256 = "sha256-H4THSBrSTEYepnA2MK1FaMxfmG6xwlAK6Q5YXlA+DRY=";
}
