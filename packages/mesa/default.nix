{
  mesa,
  fetchFromGitHub,
  mesaPatchesSrc ? fetchFromGitHub {
    name = "source";
    owner = "blu-sharky";
    repo = "piano-mesa";
    rev = "a89c1e46eef3e161520b084479928aaa5a8e8732";
    hash = "sha256-vYTaJ3lCul7MfYn/QHvYEVzkm6npRbqNnd2xc0/S/sw=";
  },
}:

mesa.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    # Newer Mesa may already know the A830v1 ID. Apply the narrow public
    # device-ID addition only when it is absent, without replacing Mesa.
    if ! grep -q 'chip_id=0xffff44050001' src/freedreno/common/freedreno_devices.py; then
      patch --batch --fuzz=0 -p1 < ${mesaPatchesSrc}/patches/0001-freedreno-Add-chip-id-support-for-A830v1.patch
    fi
  '';
})
