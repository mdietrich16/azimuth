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
      inherit (pkgs) lib;

      pkgs = import nixpkgs {
        inherit system;
        overlays = [(import rust-overlay)];
      };

      rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

      craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
      src = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          # Default files from crane (Rust and cargo files)
          (craneLib.fileset.commonCargoSources ./.)
          (craneLib.fileset.configToml ./.)
          # Also keep linker script
          ./memory.x
        ];
      };
      # src = craneLib.cleanCargoSource ./.;

      commonArgs = {
        inherit src;
        strictDeps = true;
        cargoExtraArgs = "--workspace --exclude azimuth-firmware-pico";
      };

      # Common args for embedded builds
      embeddedArgs =
        commonArgs
        // {
          cargoExtraArgs = "-p azimuth-firmware-pico --target thumbv6m-none-eabi";
          doCheck = false;
          nativeBuildInputs = with pkgs; [
            flip-link
          ];
        };

      # Build artifacts for both targets
      cargoArtifacts = {
        embedded = craneLib.buildDepsOnly embeddedArgs;
        std = craneLib.buildDepsOnly commonArgs;
      };

      individualCrateArgs = cargoArtifacts:
        commonArgs
        // {
          inherit cargoArtifacts;
          inherit (craneLib.crateNameFromCargoToml {inherit src;}) version;
          # NB: we disable tests since we'll run them all via cargo-nextest
          doCheck = false;
        };

      fileSetForCrate = crate:
        lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [
            ./Cargo.toml
            ./Cargo.lock
            ./memory.x
            (craneLib.fileset.commonCargoSources ./crates/azimuth-core)
            (craneLib.fileset.commonCargoSources ./crates/workspace-hack)
            (craneLib.fileset.commonCargoSources crate)
          ];
        };

      # Build the top-level crates of the workspace as individual derivations.
      # This allows consumers to only depend on (and build) only what they need.
      # Though it is possible to build the entire workspace as a single derivation,
      # so this is left up to you on how to organize things
      #
      # Note that the cargo workspace must define `workspace.members` using wildcards,
      # otherwise, omitting a crate (like we do below) will result in errors since
      # cargo won't be able to find the sources for all members.
      firmware-pico = craneLib.buildPackage ((individualCrateArgs cargoArtifacts.embedded)
        // {
          pname = "azimuth-firmware-pico";
          src = fileSetForCrate ./crates/azimuth-firmware-pico;
        });
      firmware-sim = craneLib.buildPackage ((individualCrateArgs cargoArtifacts.std)
        // {
          pname = "azimuth-firmware-sim";
          cargoExtraArgs = "-p azimuth-firmware-sim";
          src = fileSetForCrate ./crates/azimuth-firmware-sim;
        });
      gui = craneLib.buildPackage ((individualCrateArgs cargoArtifacts.std)
        // {
          pname = "azimuth-gui";
          cargoExtraArgs = "-p azimuth-gui";
          src = fileSetForCrate ./crates/azimuth-gui;
        });
    in {
      packages = {
        inherit firmware-pico firmware-sim gui;
        default = self.packages.${system}.firmware-sim;
        all = pkgs.symlinkJoin {
          name = "azimuth-all";
          paths = [
            firmware-pico
            firmware-sim
            gui
          ];
        };
      };

      apps = {
        firmware-pico = flake-utils.lib.mkApp {
          drv = firmware-pico;
        };
        firmware-sim = flake-utils.lib.mkApp {
          drv = firmware-sim;
        };
      };

      checks = {
        # Build the crates as part of `nix flake check` for convenience
        inherit firmware-pico firmware-sim gui;

        # Run clippy (and deny all warnings) on the workspace source,
        # again, reusing the dependency artifacts from above.
        #
        # Note that this is done as a separate derivation so that
        # we can block the CI if there are issues here, but not
        # prevent downstream consumers from building our crate by itself.
        clippy-embeded = craneLib.cargoClippy (embeddedArgs
          // {
            cargoArtifacts = cargoArtifacts.embedded;
            cargoClippyExtraArgs = "-p azimuth-firmware-pico -- --deny warnings";
          });
        clippy-std = craneLib.cargoClippy (commonArgs
          // {
            cargoArtifacts = cargoArtifacts.std;
            cargoClippyExtraArgs = "-p azimuth-gui -p azimuth-firmware-sim -- --deny warnings";
          });

        doc-embedded = craneLib.cargoDoc (embeddedArgs
          // {
            cargoArtifacts = cargoArtifacts.embedded;
          });

        doc-std = craneLib.cargoDoc (commonArgs
          // {
            cargoArtifacts = cargoArtifacts.std;
          });

        # Check formatting
        format = craneLib.cargoFmt {
          inherit src;
        };

        tomlformat = craneLib.taploFmt {
          src = pkgs.lib.sources.sourceFilesBySuffices src [".toml"];
          # taplo arguments can be further customized below as needed
          # taploExtraArgs = "--config ./taplo.toml";
        };

        # Audit dependencies
        audit = craneLib.cargoAudit {
          inherit src advisory-db;
        };

        # Audit licenses
        deny = craneLib.cargoDeny {
          inherit src;
        };

        # Run tests with cargo-nextest
        # Consider setting `doCheck = false` on other crate derivations
        # if you do not want the tests to run twice
        nextest-std = craneLib.cargoNextest (commonArgs
          // {
            cargoArtifacts = cargoArtifacts.std;
            partitions = 1;
            partitionType = "count";
          });
        nextest-embedded = craneLib.cargoNextest (embeddedArgs
          // {
            cargoArtifacts = cargoArtifacts.std;
            partitions = 1;
            partitionType = "count";
          });

        # Ensure that cargo-hakari is up to date
        hakari = craneLib.mkCargoDerivation {
          inherit src;
          pname = "hakari";
          cargoArtifacts = null;
          doInstallCargoArtifacts = false;

          buildPhaseCargoCommand = ''
            cargo hakari generate --diff  # workspace-hack Cargo.toml is up-to-date
            cargo hakari manage-deps --dry-run  # all workspace crates depend on workspace-hack
            cargo hakari verify
          '';

          nativeBuildInputs = [
            pkgs.cargo-hakari
          ];
        };
      };

      devShells.default = craneLib.devShell {
        # Inherit inputs from checks.
        checks = self.checks.${system};

        inputsFrom = [self.packages.${system}.firmware-pico self.packages.${system}.firmware-sim];

        buildInputs = with pkgs; [
          # Essential
          # rustToolchain # Rust compiler and standard tools
          rust-analyzer # IDE support

          # Cargo tools
          cargo-hakari

          # For RP2040 development
          probe-rs-tools # Flashing and debugging
          elf2uf2-rs # Converts ELF files to UF2 for the Pico
          picotool # For Pico operations
        ];
      };
    });
}
