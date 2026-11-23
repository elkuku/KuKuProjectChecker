# Installation

KuKu Project Checker is a Flutter desktop app for Linux.

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install/linux) with Linux desktop support
- `git`, for the status of the local repositories
- Optional, for the [Open in …](./open-in) menu: a file manager, Konsole or another terminal, PhpStorm, VS Code, Kate, gitk

## Build

```bash
git clone https://github.com/elkuku/KuKuProjectChecker.git
cd KuKuProjectChecker
flutter build linux --release
```

The app is in `build/linux/x64/release/bundle/`.

## Add it to the application menu

```bash
linux/packaging/install-desktop-entry.sh
```

This installs the icon and a menu entry for the release build, under **Development**.
The menu runs the release build, so rebuild it after updating the app:

```bash
git pull
flutter build linux --release
```

Run the script again only if the icon or the menu entry changed.

## First start

The list is empty at first. Add your sites with **Add site** (or ＋ in the top bar), see
[Managing sites](./settings). Each site has to report its versions, see
[Site requirements](./site-requirements).

Your sites are saved in `~/.local/share/org.elkuku.kuku_project_checker/settings.json`,
the theme choice in `preferences.json` next to it.
