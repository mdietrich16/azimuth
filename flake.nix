{
  description = "Azimuth Drone Control System";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    crane.url = "github:ipetkov/crane";

    flake-utils.url = "github:numtide/flake-utils";

    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
    crane,
    flake-utils,
    advisory-db,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [(import rust-overlay)];
      };

      rustToolchain = pkgs.rust-bin.stable.latest.default.override {
        targets = ["thumbv6m-none-eabi"]; # For RP2040
        extensions = ["llvm-tools-preview" "rust-src"];
      };

      craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
      src = craneLib.cleanCargoSource ./.;

      # Common args for embedded builds
      commonArgsEmbedded = {
        inherit src;
        strictDeps = true;
        cargoExtraArgs = "--target thumbv6m-none-eabi";
        doCheck = false;

        cargoVendorDir = craneLib.vendorCargoDeps {
          inherit src;
          cargoLock = ./Cargo.lock;
        };
      };

      # Common args for standard builds
      commonArgsStd = {
        inherit src;
        strictDeps = true;

        cargoVendorDir = craneLib.vendorCargoDeps {
          inherit src;
          cargoLock = ./Cargo.lock;
        };
      };

      # Build artifacts for both targets
      cargoArtifacts = {
        embedded = craneLib.buildDepsOnly commonArgsEmbedded;
        std = craneLib.buildDepsOnly commonArgsStd;
      };
    in {
      packages = {
        firmware-pico = craneLib.buildPackage (commonArgsEmbedded
          // {
            cargoArtifacts = cargoArtifacts.embedded;
            cargoExtraArgs = "--package azimuth-firmware-pico --target thumbv6m-none-eabi";
          });
        firmware-sim = craneLib.buildPackage (commonArgsStd
          // {
            cargoArtifacts = cargoArtifacts.std;
            cargoExtraArgs = "--package azimuth-firmware-sim";
          });
        default = self.packages.${system}.firmware-pico;
        all = pkgs.symlinkJoin {
          name = "azimuth-all";
          paths = [
            self.packages.${system}.firmware-pico
            self.packages.${system}.firmware-sim
            # self.packages.${system}.gui # Once we add it
          ];
        };
        clean = pkgs.writeScriptBin "azimuth-clean" ''
          #!${pkgs.bash}/bin/bash
          set -e
          echo "Cleaning Azimuth build artifacts..."

          # Remove result symlinks
          rm -f result*

          # Remove target directory
          rm -rf target/

          # Clean nix store (optional, uncomment if needed)
          # nix-collect-garbage -d

          echo "Clean complete!"
        '';
      };

      checks = {
        inherit (self.packages.${system}) firmware-pico;

        # Format check (works on all files)
        format = craneLib.cargoFmt {
          inherit src;
        };

        # Clippy for embedded crates
        clippy-embedded = craneLib.cargoClippy (commonArgsEmbedded
          // {
            cargoArtifacts = cargoArtifacts.embedded;
            cargoClippyExtraArgs = "--package azimuth-firmware-pico --target thumbv6m-none-eabi -- --deny warnings";
          });

        # Clippy for standard crates
        clippy-std = craneLib.cargoClippy (commonArgsStd
          // {
            cargoArtifacts = cargoArtifacts.std;
            cargoClippyExtraArgs = "--package azimuth-core --package azimuth-gui --package azimuth-firmware-sim -- --deny warnings";
          });

        # Security audit (works on all dependencies)
        audit = craneLib.cargoAudit {
          inherit src advisory-db;
        };
      };

      devShells.default = pkgs.mkShell {
        inputsFrom = [self.packages.${system}.firmware-pico self.packages.${system}.firmware-sim];
        buildInputs = with pkgs; [
          # Essential
          rustToolchain # Rust compiler and standard tools
          rust-analyzer # IDE support
          self.packages.${system}.clean # clean script, azimuth-clean

          # For RP2040 development
          probe-rs-tools # Flashing and debugging
          elf2uf2-rs # Converts ELF files to UF2 for the Pico
          picotool # For Pico operations
        ];
      };
    });
}
