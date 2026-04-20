# Roll Docker Stack

🚀 **A powerful, flexible Docker development environment for modern web applications**

Roll Docker Stack provides pre-configured Docker environments for various frameworks and CMS platforms, making it easy to spin up consistent development environments with all the tools you need.

## 🌟 Features

- **Multi-Framework Support**: Magento 2, Laravel, Symfony, TYPO3, Shopware, WordPress, and more
- **Service Integration**: PHP-FPM, Nginx, MySQL/MariaDB, Redis, Elasticsearch, RabbitMQ, Varnish
- **Developer Tools**: Xdebug, MailPit (Better Mailhog Alternative), Redis Insight, ElasticVue, and more
- **Cross-Platform**: macOS, Linux, and Windows (WSL2) support
- **Local Development**: Optimized for local development environments
- **Easy Configuration**: Environment-specific settings with sensible defaults

## 🚀 Installation

### Installing via Homebrew (Recommended)

RollDev may be installed via Homebrew on both macOS and Linux hosts:

```bash
brew install epartment/roll/roll
roll svc up
```

**Updating via Homebrew:**
```bash
brew upgrade epartment/roll/roll
roll svc restart
```


### Windows Installation (via WSL2)

1. Install and enable WSL2 in Windows 10
2. Install Ubuntu 20.04 or other compatible Linux version from the Windows store
3. Launch Docker for Windows, ensure WSL2 integration is enabled
4. Launch WSL from your terminal:

```bash
wsl
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
brew install epartment/roll/roll
roll svc up
```

> **⚠️ Performance Warning**: For optimal performance, code should be located in the WSL Linux home path (`~/code/projectname`) NOT the default `/mnt/c` path mapping.

> **💡 GUI Tools**: Windows GUI tools should use network paths: `\\wsl$\Ubuntu-20.04\home\<USER>\<PROJECTPATH>`

## ⚙️ Next Steps

### Automatic DNS Resolution

- **Linux**: Configure DNS to resolve `*.test` to `127.0.0.1` or use `/etc/hosts` entries
- **macOS**: Automatic via BSD per-TLD resolver at `/etc/resolver/test`
- **Windows**: Manual configuration of network adapter DNS server required

### Trusted CA Root Certificate

RollDev uses a CA root certificate for trusted SSL certificates. The CA root is located at `~/.roll/ssl/rootca/certs/ca.cert.pem`.

- **macOS**: Automatically added to Keychain (search for 'RollDev Proxy Local CA')
- **Linux**: Added to system trust bundle automatically
- **Firefox**: Import CA manually via Preferences → Privacy & Security → View Certificates → Authorities → Import
- **Chrome (Linux)**: Import CA via Settings → Privacy And Security → Manage Certificates → Authorities → Import

## 📚 Full Documentation

For complete installation instructions, configuration options, troubleshooting, and advanced usage, visit our comprehensive documentation:

**👉 [epartment.github.io/rolldev](https://epartment.github.io/rolldev)**

## 🛠️ Supported Environments

- **Magento 2** - Complete e-commerce development stack
- **Magento 1** - Legacy Magento support
- **Laravel** - Modern PHP framework environment
- **Symfony** - Professional PHP development
- **TYPO3** - Enterprise CMS platform
- **Shopware** - E-commerce platform
- **WordPress** - Popular CMS environment
- **Akeneo** - PIM platform support
- **PHP** - Generic PHP development environment

## 🤝 Contributing

We welcome contributions! Please see our [contribution guidelines](https://epartment.github.io/rolldev/contributing/) for details.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Documentation**: [epartment.github.io/rolldev](https://epartment.github.io/rolldev)
- **CLI Repository**: [github.com/epartment/rolldev](https://github.com/epartment/rolldev)
- **Issues**: [github.com/epartment/rolldev/issues](https://github.com/epartment/rolldev/issues)
- **Container Packages**: [github.com/orgs/epartment/packages](https://github.com/orgs/epartment/packages?repo_name=rolldev)
