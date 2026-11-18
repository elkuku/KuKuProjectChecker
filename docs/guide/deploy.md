# Deploying

A site whose local repository has a **deploy remote** can be deployed from the app: it pushes the
current branch to that remote, and the server (e.g. Plesk with automatic deployment) deploys the
new version.

The deploy remote is the first git remote that is not `origin` and not an HTTP(S) address, e.g.:

```bash
git remote add production user@server:~/git/shop.git
```

## Deploy

When the deploy remote is missing commits, the site's row shows a 🚀 button with their number.
The ⋮ menu has **Deploy** too.

The app asks first, and says what the push includes:

![Deploy confirmation](../screenshots/06_deploy_confirm-dark.png){.theme-dark}
![Deploy confirmation](../screenshots/06_deploy_confirm-light.png){.theme-light}

- **Uncommitted files** are not included: only commits are pushed.
- **Commits not pushed to the upstream** (e.g. GitHub) yet are deployed anyway; push them there too.

**Deploy** runs `git push <deploy remote> <branch>` and shows git's output:

![Deploy done](../screenshots/07_deploy_done-dark.png){.theme-dark}
![Deploy done](../screenshots/07_deploy_done-light.png){.theme-light}

Afterwards the list is read again, and the site shows `clean, deployed` once everything is deployed.

::: tip SSH passphrase
The app has no terminal, so a graphical program asks for the passphrase of your SSH key:
`ksshaskpass` on KDE, otherwise `ssh-askpass` if it is installed (or whatever `SSH_ASKPASS` points to).
:::

::: info After the push
The app only pushes. Whether the server's deploy script succeeded shows in the server's deploy log,
e.g. in Plesk or with the deploy log page of the
[KuKu system tools bundle](https://github.com/elkuku/SFSystemToolsBundle#readme).
:::
