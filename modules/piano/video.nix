{ ... }:

{
  nixpkgs.overlays = [
    (
      final: prev:
      let
        patch = ffmpeg: final.callPackage ../../packages/ffmpeg { inherit ffmpeg; };
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
      }
    )
  ];
}
