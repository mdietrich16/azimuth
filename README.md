## Development Setup

This project uses Nix flakes for development environment management.

### Quick Start
```bash
# Clone the repository
git clone https://github.com/your/azimuth.git
cd azimuth

# If using direnv
direnv allow

# Otherwise
nix develop

# For non-flake users
nix-shell
```

### Environment Variables
Copy `.env.example` to `.env` and adjust as needed:
```bash
cp .env.example .env
```
## License

Licensed under either of

 * Apache License, Version 2.0
   ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
 * MIT license
   ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

## Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.

