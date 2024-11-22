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
