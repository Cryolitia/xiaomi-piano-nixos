{
  lib,
  stdenv,
  python3,
  bash,
  coreutils,
  gnugrep,
  gawk,
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
  sunuefiSrc ? callPackage ../sunuefi-source.nix { },
}:

let
  debianPianoSrc = fetchFromGitHub {
    name = "source";
    owner = "blu-sharky";
    repo = "debian-piano";
    rev = "a75f8c5d5fa099d65c171ac839c2e3bb6c63ec45";
    hash = "sha256-ji67l4DmgMLKlggkVtBbGWvVS/Aw5JeyQcuKuHAls4A=";
  };
  audioReachSrc = fetchFromGitHub {
    name = "source";
    owner = "linux-msm";
    repo = "audioreach-topology";
    rev = "993a17dcb672357998a463a73f120064d6c74f4f";
    hash = "sha256-L2qem2uUvV/AgQRZCl/LOmAdaWyc13pDTlNjEXDtgVc=";
  };
  runtimePython = python3.withPackages (ps: [ ps.pygobject3 ]);
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

    python3 ${./transform.py} prepare "$PWD" ${debianPianoSrc}

    make -C linux/userspace/pen OUT="$PWD/pen-build" \
      CC="$CC" CXX="$CXX" AR="$AR" LDLIBS=-lm
    $CC -O2 -Ilinux/userspace/pen -c piano-touch-view.c -o touch.o
    $CXX touch.o pen-build/libpiano-pen-core.a -lm -o piano-touch-view

    bash ${debianPianoSrc}/scripts/build-topology.sh ${audioReachSrc} "$PWD/firmware"

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
      --shell ${bash}/bin/bash --python ${runtimePython}/bin/python3

    install -Dm755 piano-touch-view "$out/bin/piano-touch-view"
    install -Dm755 pen-build/piano-pen-offline "$out/bin/piano-pen-offline"
    mkdir -p "$out/lib"
    cp -r firmware "$out/lib/firmware"

    wrapProgram "$out/libexec/piano/touch-input" \
      --prefix PATH : ${lib.makeBinPath [ gawk ]}
    wrapProgram "$out/libexec/piano/pen-bluetooth" \
      --prefix GI_TYPELIB_PATH : ${lib.getLib glib}/lib/girepository-1.0
    wrapProgram "$out/libexec/piano/bluetooth-address.py" \
      --prefix PATH : ${lib.makeBinPath [ util-linux ]}
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
    install -Dm644 linux/userspace/pen/Apache-2.0.txt "$out/share/licenses/piano-bsp/Apache-2.0.txt"

    runHook postInstall
  '';

  passthru = { inherit debianPianoSrc; };

  meta = {
    description = "Xiaomi Pad 8 Pro touch input, ALSA profiles and hardware diagnostics";
    platforms = lib.platforms.linux;
    license = with lib.licenses; [
      mit
      bsd2Patent
      asl20
    ];
  };
}
