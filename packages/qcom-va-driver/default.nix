{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  glslang,
  libdrm,
  libgbm,
  libglvnd,
  libva,
  vulkan-headers,
  vulkan-loader,
}:

stdenv.mkDerivation {
  pname = "qcom-va-driver";
  version = "1.1.1-unstable-2026-10-28";

  src = fetchFromGitHub {
    owner = "radxa-pkg";
    repo = "qcom-va-driver";
    rev = "0980a1decf26d34c9aa71cd0a4a0d25703a7a17f";
    hash = "sha256-jBqsPU/xReoQLyI01N83w848nNj+87w0ol5ESNUwI9E=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    glslang
  ];

  buildInputs = [
    libdrm
    libgbm
    libglvnd
    libva
    vulkan-headers
    vulkan-loader
  ];

  mesonFlags = [
    (lib.mesonOption "gpu_copy" "enabled")
    (lib.mesonOption "cdsp_vpp" "disabled")
    (lib.mesonOption "vulkan_vpp" "enabled")
    (lib.mesonBool "v4l2_symlink" false)
  ];

  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  meta = {
    description = "VA-API driver for Qualcomm Iris video codecs";
    homepage = "https://github.com/radxa-pkg/qcom-va-driver";
    license = lib.licenses.mit;
    platforms = [ "aarch64-linux" ];
  };
}
