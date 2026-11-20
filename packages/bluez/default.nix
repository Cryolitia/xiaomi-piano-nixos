{
  lib,
  bluez,
  fetchurl,
  sunuefiSrc,
}:

let
  version = "5.88";
  base =
    if bluez.version == "5.87" then
      bluez.overrideAttrs (old: {
        inherit version;
        src = fetchurl {
          url = "mirror://kernel/linux/bluetooth/bluez-${version}.tar.xz";
          hash = "sha256-aVLDnrX4sO5xLMUKs7z/A74XxBDdl8pkD0hJ2aFlO6M=";
        };

        # 5.88 contains the UUID discovery fix and removed some readline tools.
        # Retain nixpkgs' readline linkage for the tools still present.
        patches = [ ];
        postPatch = ''
          substituteInPlace Makefile.tools --replace-fail '-lreadline' '$(READLINE_LIBS)'
          substituteInPlace configure.ac \
            --replace-fail 'AC_CHECK_HEADERS(readline/readline.h, enable_readline=yes,
                          AC_MSG_ERROR(readline header files are required))' \
            'PKG_CHECK_MODULES([READLINE], [readline], enable_readline=yes)'
        ''
        + (old.postPatch or "");

        # BlueZ 5.88 no longer ships gatttool.
        postInstall =
          lib.replaceString "install -Dm755 attrib/gatttool $out/bin/gatttool" ""
            old.postInstall;
      })
    else
      bluez;
in
import ../sunuefi-patches.nix {
  inherit lib sunuefiSrc;
  package = base;
  component = "bluez";
  seriesVersion = version;
}
