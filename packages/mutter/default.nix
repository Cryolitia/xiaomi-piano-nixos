{ mutter }:

mutter.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./patches/native-hdr-profiles.patch ];
})
