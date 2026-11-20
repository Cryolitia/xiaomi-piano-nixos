{
  lib,
  stdenv,
  python3,
  bash,
  coreutils,
  gnugrep,
  util-linux,
  iproute2,
  git,
  patch,
  makeWrapper,
  m4,
  alsa-utils,
  glib,
  callPackage,
  fetchFromGitHub,
  fetchurl,
  fetchzip,
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
  withPen ? false,
}:

let
  debianPianoSrc = fetchFromGitHub {
    name = "source";
    owner = "blu-sharky";
    repo = "debian-piano";
    rev = "a75f8c5d5fa099d65c171ac839c2e3bb6c63ec45";
    hash = "sha256-ji67l4DmgMLKlggkVtBbGWvVS/Aw5JeyQcuKuHAls4A=";
  };
  audioReach =
    (builtins.fromJSON (builtins.readFile "${sunuefiSrc}/sources.lock.json")).audioreach-topology;
  audioReachSrc = fetchzip {
    name = "source";
    url = "${lib.removeSuffix ".git" audioReach.url}/archive/${audioReach.commit}.tar.gz";
    hash = "sha256-J/xqKMa428ScOa/WOvoRopZpo2L70w78XRp8v7JHKRY=";
  };
  speakerDap =
    (builtins.fromJSON (builtins.readFile "${sunuefiSrc}/config/release.json")).audio_topology.speaker_dap;
  speakerAcdb = fetchurl {
    name = "Mi_acdb_cal.acdb";
    url = speakerDap.acdb_url;
    sha256 = builtins.head speakerDap.acdb_sha256;
  };
  runtimePython = if withPen then python3.withPackages (ps: [ ps.pygobject3 ]) else python3;
in
stdenv.mkDerivation {
  pname = "piano-bsp";
  version = "1";
  src = sunuefiSrc;
  nativeBuildInputs = [
    python3
    git
    patch
    makeWrapper
    m4
    alsa-utils
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    python3 ${./transform.py} prepare "$PWD" ${debianPianoSrc} ${audioReachSrc} ${speakerAcdb}

    runHook postBuild
  '';

  # alsatplg is a native build tool; this also works when cross compiling.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    alsatplg -d "firmware/qcom/sm8750/Xiaomi Pad 8 Pro-tplg.bin" -o topology-decoded.conf
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    python3 ${./transform.py} install \
      --sunuefi "$PWD" --output "$out" \
      --shell ${bash}/bin/bash --python ${runtimePython}/bin/python3 \
      ${lib.optionalString withPen "--with-pen"}

    ${lib.optionalString withPen ''
      wrapProgram "$out/libexec/piano/pen-control" \
        --prefix GI_TYPELIB_PATH : ${lib.getLib glib}/lib/girepository-1.0
    ''}

    mkdir -p "$out/lib"
    cp -r firmware/. "$out/lib/firmware/"

    wrapProgram "$out/libexec/piano/usb-network" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          gnugrep
          util-linux
          iproute2
        ]
      }

    install -Dm644 ${sunuefiSrc}/LICENSE.md "$out/share/licenses/piano-bsp/LICENSE.sunuefi.md"
    install -Dm644 ${debianPianoSrc}/LICENSE "$out/share/licenses/piano-bsp/LICENSE.debian-piano"

    runHook postInstall
  '';

  passthru = { inherit debianPianoSrc withPen; };

  meta = {
    description = "Xiaomi Pad 8 Pro board support and optional stylus input";
    platforms = lib.platforms.linux;
    license = with lib.licenses; [
      mit
      bsd2Patent
      asl20
    ];
  };
}
