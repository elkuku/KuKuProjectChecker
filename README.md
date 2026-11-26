# KuKu Project Checker

[![Dart](https://github.com/elkuku/KuKuProjectChecker/actions/workflows/dart.yml/badge.svg)](https://github.com/elkuku/KuKuProjectChecker/actions/workflows/dart.yml)

Your Symfony sites at a glance: the PHP and Symfony versions of every site, and what is not yet
committed, pushed or deployed in its local repository. Shows the uncommitted changes with their
diffs, deploys with one click, and opens a project in the browser, the file manager, a terminal,
PhpStorm or VS Code. It can also show the read-only status report of a KMyServer.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/01_sites-dark.png">
  <img src="docs/screenshots/01_sites-light.png" alt="The site list" width="480">
</picture>

**Documentation:** https://elkuku.github.io/KuKuProjectChecker/

## Quick start

```bash
flutter build linux --release
linux/packaging/install-desktop-entry.sh
```

Made with Dart and Flutter.
