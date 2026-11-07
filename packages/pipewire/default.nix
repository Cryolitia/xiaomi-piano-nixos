{
  pipewire,
  fetchurl,
}:

pipewire.overrideAttrs (old: {
  # Keep preferred camera sizes through Gst caps conversion, including the
  # upstream prerequisites, and retain a running format when it still fits.
  patches = (old.patches or [ ]) ++ [
    (fetchurl {
      url = "https://github.com/PipeWire/pipewire/commit/c4309f0eb5667f15c6c98a3ab19ea2c6f45afa3e.patch";
      hash = "sha256-G/x1RmgbTwOtKoHKvefZi3CmR08drzQaG4MMcPxGfTM=";
    })
    (fetchurl {
      url = "https://github.com/PipeWire/pipewire/commit/acea30afaaa0022f9ea134ce876cea12b1b1bcf0.patch";
      hash = "sha256-+WIkISsX0sosHKn71bE61leQIvfHloQUKlOUiYjv6+I=";
    })
    (fetchurl {
      url = "https://github.com/PipeWire/pipewire/commit/18244c9741dda4d5c48df29d15834f25ef97da2b.patch";
      hash = "sha256-K3Z8wexZl7JwLCRora2Y0OxH5XUtJibZcGQQhpP+XR4=";
    })
    (fetchurl {
      url = "https://github.com/PipeWire/pipewire/commit/97699d707df374773fe5d6e32ea7362ef8dcf51b.patch";
      hash = "sha256-B9TLP0GTP+oNgobLWxkDUrnOekDeLmSkTRDuKLpDc+8=";
    })
  ];
})
