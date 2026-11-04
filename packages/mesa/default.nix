{ mesa, mesaPatchesSrc }:

mesa.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    # Newer Mesa may already know the A830v1 ID. Apply the narrow public
    # device-ID addition only when it is absent, without replacing Mesa.
    if ! grep -q 'chip_id=0xffff44050001' src/freedreno/common/freedreno_devices.py; then
      patch --batch --fuzz=0 -p1 < ${mesaPatchesSrc}/patches/0001-freedreno-Add-chip-id-support-for-A830v1.patch
    fi
  '';
})
