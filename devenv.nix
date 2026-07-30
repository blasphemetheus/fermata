{ pkgs, lib, ... }:

let
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
  ];

  env = {
    ERL_AFLAGS = "-kernel shell_history enabled";
  };

  enterShell = ''
    export MIX_HOME="$PWD/.nix-mix"
    export HEX_HOME="$PWD/.nix-hex"
    mkdir -p "$MIX_HOME" "$HEX_HOME"
    export PATH="$MIX_HOME/bin:$MIX_HOME/escripts:$HEX_HOME/bin:$PATH"
  '';
}
