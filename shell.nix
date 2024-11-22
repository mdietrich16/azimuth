# shell.nix
let
  # Use flake.nix as single source of truth
  flake = builtins.getFlake (toString ./.);

  # For non-flake systems, provide nixpkgs
  pkgs = import <nixpkgs> {};

  # Get system-specific attributes
  system = builtins.currentSystem;
in
  {pkgs ? import <nixpkgs> {}}:
    pkgs.mkShell {
      # Import all packages from flake's devShell
      inputsFrom = [(flake.devShells.${system}.default)];

      # Add any additional legacy-specific packages
      buildInputs = [];

      # Mirror your flake shell's environment
      shellHook = ''
        echo "Entering Azimuth development environment (legacy shell)"
      '';
    }
