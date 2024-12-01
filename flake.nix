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

      crateTargets = {
        "x86_64-unknown-linux-gnu" = ["azimuth-drone" "gauge"];
        "thumbv6m-none-eabi" = ["azimuth-drone" "delta"];
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

      otherSrc = lib.cleanSourceWith {
        src = ./.;
        filter = path: type: (craneLib.filterCargoSources path type) || (builtins.baseNameOf path == "memory.x");
      };

      commonArgs = {
        inherit src;
        # cargoExtraArgs = lib.strings.concatMapStrings (x: "-p ${x} ") crateTargets.x86_64-unknown-linux-gnu;
        nativeBuildInputs = with pkgs; [
          flip-link
        ];
        doCheck = false;
        extraDummyScript = ''
          cp -a ${./memory.x} $out/memory.x
          # (shopt -s globstar; rm -rf $out/**/src/bin/crane-dummy-*)
        '';
      };

      # Common args for embedded builds
      embeddedArgs =
        commonArgs
        // {
          cargoExtraArgs = lib.strings.concatStrings ["--target thumbv6m-none-eabi " (lib.strings.concatMapStrings (x: "-p ${x} ") crateTargets.thumbv6m-none-eabi)];
          nativeBuildInputs = with pkgs; [
            flip-link
          ];
        };

      cargoArtifacts = craneLib.buildDepsOnly commonArgs;

      azimuth-pico = craneLib.buildPackage (embeddedArgs
        // {
          inherit cargoArtifacts;
          # cargoArtifacts = cargoArtifacts.embedded;
          pname = "azimuth-pico";
          cargoExtraArgs = "-p azimuth-drone";
          src = src;
        });
      azimuth-sim = craneLib.buildPackage (commonArgs
        // {
          inherit cargoArtifacts;
          # cargoArtifacts = cargoArtifacts.std;
          pname = "azimuth-sim";
          cargoExtraArgs = "-p azimuth-drone";
          src = src;
        });
      gauge = craneLib.buildPackage (commonArgs
        // {
          inherit cargoArtifacts;
          # cargoArtifacts = cargoArtifacts.std;
          pname = "azimuth-gui";
          cargoExtraArgs = "-p gauge";
          src = src;
        });
      delta = craneLib.buildPackage (embeddedArgs
        // {
          inherit cargoArtifacts;
          # cargoArtifacts = cargoArtifacts.embedded;
          pname = "azimuth-gui";
          cargoExtraArgs = "-p delta";
          src = src;
        });
    in {
      packages = {
        inherit azimuth-pico azimuth-sim gauge delta;
        default = self.packages.${system}.azimuth-pico;
        all = pkgs.symlinkJoin {
          name = "azimuth-all";
          paths = [
            azimuth-pico
            azimuth-sim
            gauge
            delta
          ];
        };
      };

      apps = {
        azimuth-sim = flake-utils.lib.mkApp {
          drv = azimuth-sim;
        };
        gauge = flake-utils.lib.mkApp {
          drv = gauge;
        };
      };

      checks = {
        # Build the crates as part of `nix flake check` for convenience
        inherit azimuth-pico azimuth-sim gauge delta;

        # Run clippy (and deny all warnings) on the workspace source,
        # again, reusing the dependency artifacts from above.
        #
        # Note that this is done as a separate derivation so that
        # we can block the CI if there are issues here, but not
        # prevent downstream consumers from building our crate by itself.
        # clippy-embeded = craneLib.cargoClippy (embeddedArgs
        #   // {
        #     cargoArtifacts = cargoArtifacts.embedded;
        #     cargoClippyExtraArgs = "-p azimuth-firmware-pico -- --deny warnings";
        #   });
        # clippy-std = craneLib.cargoClippy (commonArgs
        #   // {
        #     cargoArtifacts = cargoArtifacts.std;
        #     cargoClippyExtraArgs = "-p azimuth-gui -p azimuth-firmware-sim -- --deny warnings";
        #   });

        # doc-embedded = craneLib.cargoDoc (embeddedArgs
        #   // {
        #     cargoArtifacts = cargoArtifacts.embedded;
        #   });

        # doc-std = craneLib.cargoDoc (commonArgs
        #   // {
        #     cargoArtifacts = cargoArtifacts.std;
        #   });

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
          cargoDenyExtraArgs = "--exclude workspace-hack";
          inherit src;
        };

        # Run tests with cargo-nextest
        # Consider setting `doCheck = false` on other crate derivations
        # if you do not want the tests to run twice
        # nextest-std = craneLib.cargoNextest (commonArgs
        #   // {
        #     cargoArtifacts = cargoArtifacts.std;
        #     partitions = 1;
        #     partitionType = "count";
        #   });
        # nextest-embedded = craneLib.cargoNextest (embeddedArgs
        #   // {
        #     cargoArtifacts = cargoArtifacts.std;
        #     partitions = 1;
        #     partitionType = "count";
        #   });

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

      inherit src otherSrc;

      devShells.default = craneLib.devShell {
        # Inherit inputs from checks.
        checks = self.checks.${system};

        inputsFrom = [self.packages.${system}.azimuth-pico self.packages.${system}.azimuth-sim self.packages.${system}.gauge self.packages.${system}.delta];

        packages = with pkgs; [
          # Essential
          # rustToolchain # Rust compiler and standard tools
          rust-analyzer # IDE support

          # Cargo tools
          cargo-hakari
          cargo-binutils
          minicom

          # For RP2040 development
          probe-rs-tools # Flashing and debugging
          elf2uf2-rs # Converts ELF files to UF2 for the Pico
          picotool # For Pico operations
        ];
      };
    });
}
