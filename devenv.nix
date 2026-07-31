{ pkgs, lib, ... }:

let
  cuda = pkgs.cudaPackages;

  # Not in nixpkgs; a plain cmake build. The resource directory is baked
  # in from CMAKE_INSTALL_PREFIX, so `verovio` works with no -r flag.
  verovio = pkgs.stdenv.mkDerivation {
    pname = "verovio";
    version = "6.2.1";
    src = pkgs.fetchFromGitHub {
      owner = "rism-digital";
      repo = "verovio";
      rev = "version-6.2.1";
      hash = "sha256-j3xYE2QZgm9We8of9sUdIfcv5/3noYAv2zRHuJg+Lp4=";
    };
    nativeBuildInputs = [ pkgs.cmake ];
    cmakeDir = "../cmake";
    # Normally generated from .git by tools/get_git_commit.sh, which
    # races with parallel compilation and has no .git here anyway.
    postPatch = ''
      echo '#define GIT_COMMIT ""' > include/vrv/git_commit.h
    '';
  };
in
{
  # Elixir + Erlang, same versions as edifice/exphil
  languages.elixir = {
    enable = true;
    package = pkgs.elixir_1_18;
  };
  languages.erlang = {
    enable = true;
    package = pkgs.erlang_27;
  };

  packages = [
    pkgs.git

    # Engraving pipeline (lib/fermata/render.ex shells out to these)
    verovio
    pkgs.lilypond
    pkgs.librsvg # rsvg-convert: SVG -> PNG/PDF

    # CUDA for EXLA on the 5090 (same set as edifice's devenv)
    cuda.cuda_nvcc
    cuda.cuda_nvrtc
    cuda.cuda_cudart
    cuda.cuda_cccl
    cuda.cudnn
    cuda.libcublas
    cuda.libcusolver
    cuda.libcufft
    cuda.libcusparse
    cuda.libcurand
    cuda.libnvjitlink
    cuda.nccl
  ];

  env = {
    ERL_AFLAGS = "-kernel shell_history enabled";
    # Explicit, never autodetected: nvcc-based autodetection silently
    # falls back to CPU (CLAUDE.md / PLAN.md open question 1).
    EXLA_TARGET = "cuda";
    XLA_TARGET = "cuda12";
    XLA_FLAGS = "--xla_gpu_cuda_data_dir=${cuda.cuda_nvcc}";
  };

  # /run/opengl-driver/lib is where NixOS puts the NVIDIA driver's
  # libcuda.so.
  env.LD_LIBRARY_PATH =
    lib.makeLibraryPath [
      pkgs.stdenv.cc.cc.lib
      pkgs.zlib
      cuda.cuda_cudart
      cuda.cuda_nvrtc
      cuda.cudnn
      cuda.libcublas
      cuda.libcusolver
      cuda.libcufft
      cuda.libcusparse
      cuda.libcurand
      cuda.libnvjitlink
      cuda.nccl
    ]
    + ":/run/opengl-driver/lib";

  enterShell = ''
    export MIX_HOME="$PWD/.nix-mix"
    export HEX_HOME="$PWD/.nix-hex"
    mkdir -p "$MIX_HOME" "$HEX_HOME"
    export PATH="$MIX_HOME/bin:$MIX_HOME/escripts:$HEX_HOME/bin:$PATH"

    # The XLA cuda12 prebuilts link libnvshmem_host.so.3, which nixpkgs
    # does not package. One-time setup (any pip):
    #   pip install --target=.nvshmem nvidia-nvshmem-cu12
    export LD_LIBRARY_PATH="$PWD/.nvshmem/nvidia/nvshmem/lib:$LD_LIBRARY_PATH"
  '';
}
