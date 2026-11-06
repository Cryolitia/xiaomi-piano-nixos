{ ... }:

{
  nixpkgs.overlays = [
    (
      final: prev:
      let
        patch = ffmpeg: final.callPackage ../../packages/ffmpeg { inherit ffmpeg; };

        # Chromium builds its own FFmpeg. Keep its compile-only codec and
        # PipeWire inputs separate from the system codec overlay; the wrapper
        # still uses the final PipeWire and GTK libraries at runtime.
        browserInputs = import prev.path {
          localSystem = prev.stdenv.hostPlatform;
          inherit (prev) config;
        };
      in
      {
        ffmpeg_7 = patch prev.ffmpeg_7;
        ffmpeg_7-headless = patch prev.ffmpeg_7-headless;
        ffmpeg_7-full = patch prev.ffmpeg_7-full;
        ffmpeg_9 = patch prev.ffmpeg_9;
        ffmpeg_9-headless = patch prev.ffmpeg_9-headless;
        ffmpeg_9-full = patch prev.ffmpeg_9-full;

        ffmpeg = final.ffmpeg_9;
        ffmpeg-headless = final.ffmpeg_9-headless;
        ffmpeg-full = final.ffmpeg_9-full;

        chromium = prev.chromium.override {
          newScope = scope: final.newScope (scope // { inherit (browserInputs) ffmpeg pipewire; });
        };
      }
    )
  ];
}
