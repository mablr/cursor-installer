# Cursor AppImage Installer

A bash script for installing and managing [Cursor](https://cursor.sh/) on Debian/Ubuntu-based Linux distributions.

## Quickstart

Just run the setup script to install and configure Cursor:
```bash
curl -sSL https://raw.githubusercontent.com/mablr/cursor-installer/master/setup.sh | bash -s -- -a
```

Or clone this repository and then run the setup script:
```
git clone https://github.com/mablr/cursor-installer
cd cursor-installer
chmod +x setup.sh
./setup.sh -a
```

## Features

- Downloads the latest Cursor AppImage
- Creates desktop launcher
- Adds `cursor` command to path
- Checks installation status
- Simple command-line interface

## Roadmap

- [x] Implement all features available in the [`cursor-setup-wizard`](https://github.com/jorcelinojunior/cursor-setup-wizard/)
- [x] AppImage download url retrieval through official Cursor API
- [x] Support any Debian-based OS
- [ ] Uninstaller feature
- [ ] Fix Cursor installation status check in Cursor Terminal for `cursor` command (yes that's deep)
- [ ] Fully unprivileged configuration
- [ ] Integration with Cursor's internal auto-update mechanism


## Usage

```bash
$ ./setup.sh --help

Usage: ./setup.sh [OPTIONS]

Options:
  -a, --all             All-in-one Cursor installation (Recommended)

  -f, --fetch           Only fetch latest Cursor AppImage 
  -c, --configure       Configure desktop launcher and CLI

  -s, --status          Check Cursor installation status

  -h, --help            Show help message
  -v, --verbose         Increase verbosity
  -q, --quiet           Show only errors

Examples:
  ./setup.sh --all               # Complete installation
  ./setup.sh --fetch             # Only fetch latest version, existing configuration will be preserved
  ./setup.sh --configure         # Configure desktop launcher and CLI for latest downloaded version
  ./setup.sh --status            # Check the status of installed Cursor version
```

## Acknowledgements

This project is based on work by [Jorcelino Junior](https://github.com/jorcelinojunior/cursor-setup-wizard/), adapted under MIT license.

## License

MIT (c) Mablr