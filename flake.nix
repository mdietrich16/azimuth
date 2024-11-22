{
  description = "Azimuth Drone Control System";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
    };
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
    crane,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      overlays = [(import rust-overlay)];
    };

    rustToolchain = pkgs.rust-bin.stable.latest.default.override {
      targets = ["thumbv6m-none-eabi"]; # For RP2040
      extensions = ["llvm-tools-preview" "rust-src"];
    };

    craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
  in {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = with pkgs; [
        # Essential
        rustToolchain # Rust compiler and standard tools
        rust-analyzer # IDE support

        # For RP2040 development
        probe-rs-tools # Flashing and debugging
        elf2uf2-rs # Converts ELF files to UF2 for the Pico
      ];
    };
  };
}
