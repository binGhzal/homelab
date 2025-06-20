# Proxmox Template Creator

A streamlined system to create and manage VM templates in Proxmox environments with a single command installation.

Please click this button to access the full wiki: [![GitBook](https://img.shields.io/badge/GitBook-%23000000.svg?style=for-the-badge&logo=gitbook&logoColor=white)](https://bizarreindustries.gitbook.io/homelab)

## Overview

The Proxmox Template Creator provides a comprehensive solution for creating and managing VM templates, container workloads, infrastructure as code, and monitoring - all from a user-friendly whiptail interface.

### Key Features

- **One-Command Installation**: Get started with a single curl command
- **50+ Linux Distributions**: Support for all major Linux distributions
- **Container Workloads**: Integrated Docker and Kubernetes setup
- **Infrastructure as Code**: Terraform and Ansible integration
- **Monitoring**: Built-in Prometheus, Grafana, and alerts
- **User-Friendly**: Whiptail-based UI with intuitive navigation

## Quick Start

Simply run this command to get started:

```bash
curl -sSL https://raw.githubusercontent.com/binghzal/homelab/main/scripts/bootstrap.sh | bash
```

This single command handles everything:

- Downloads and installs all dependencies
- Clones the repository to the appropriate location
- Sets up automatic updates
- Launches the whiptail-based UI

## System Architecture

```ascii
┌────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                │     │                 │     │                 │
│  Single curl   ├────►│  Bootstrap      ├────►│  Main           │
│    Command     │     │  Script         │     │  Controller     │
│                │     │                 │     │                 │
└────────────────┘     └─────────────────┘     └────┬────────────┘
                                                    │
                                                    ▼
┌────────────────┬─────────────────┬──────────────────┬─────────────────┐
│                │                 │                  │                 │
│  Template      │  Container      │  Terraform       │  Monitoring     │
│  Creation      │  Workloads      │  Integration     │  Stack          │
│                │                 │                  │                 │
└────────────────┴─────────────────┴──────────────────┴─────────────────┘
```

## Documentation

For detailed documentation:

- **[System Design](docs/SYSTEM_DESIGN.md)**: Comprehensive architecture and implementation details
- **[Progress Tracker](docs/PROGRESS_TRACKER.md)**: Current implementation status of all features
- **[Contributing](CONTRIBUTING.md)**: How to contribute to this project

## Requirements

- Proxmox Virtual Environment 7.0 or higher
- Root privileges for installation and operations
- Internet connection for downloading distributions and updates

## Support

If you encounter issues or have questions:

1. Check the [System Design](docs/SYSTEM_DESIGN.md) and [Progress Tracker](docs/PROGRESS_TRACKER.md)
2. Review existing [GitHub Issues](https://github.com/binghzal/homelab/issues)
3. Create a new issue with detailed information

## License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.

## Resources & References

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Cloud-Init Documentation](https://cloud-init.readthedocs.io/)
- [Christian Lempa's Boilerplates](https://github.com/christianlempa/boilerplates)

Enjoy your homelab journey! 🚀
