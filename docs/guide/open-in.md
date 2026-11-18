# Open in …

The ⋮ button of a site opens it in other apps.

![The Open in menu](../screenshots/03_open_in_menu.png)

| Entry | Opens |
|---|---|
| **Browser** | The site. |
| **Changes** | The [uncommitted changes](./changes) of the local repository. |
| **File manager** | The repository folder (`xdg-open`, e.g. Dolphin). |
| **Terminal** | A terminal in the repository folder: Konsole, GNOME Terminal, Xfce Terminal or kitty. |
| **PhpStorm** | The project in PhpStorm. |
| **VS Code** | The project in VS Code (or VSCodium). |
| **Kate** | The folder in Kate. |
| **gitk (history)** | The history of all branches. |

Only **Browser** is shown for a site without a local repository, and only the apps that are installed
are listed.

::: tip PhpStorm from the JetBrains Toolbox
Apps started from the desktop menu don't get your shell's `PATH`. Besides the `PATH`, the app
looks in `~/.local/bin` and `~/.local/share/JetBrains/Toolbox/scripts`, where the Toolbox puts its
`phpstorm` launcher. Enable the shell scripts in the Toolbox settings if PhpStorm is missing.
:::

The apps keep running when you close the checker.
