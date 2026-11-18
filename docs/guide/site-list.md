# The site list

Each site is a card with its name, its address, its versions and, if a local repository is set,
the state of that repository.

![The site list](../screenshots/01_sites-dark.png){.theme-dark}
![The site list](../screenshots/01_sites-light.png){.theme-light}

## Versions

- **PHP** and **Symfony**: the versions the site reports, see [Site requirements](./site-requirements).
- **Not reachable**: the site didn't answer, or it has no `/system/info/` endpoint.

## Repository status

The line at the bottom shows the branch of the local repository and what is pending:

| Shown | Meaning |
|---|---|
| ✅ `clean, deployed` | Everything is committed, pushed and deployed. |
| ✅ `clean` | Everything is committed and pushed; the repository has no deploy remote. |
| `3 uncommitted` | Modified, new or deleted files. Tap the card to see them, see [Uncommitted changes](./changes). |
| `1 unpushed` | Commits that are not on the upstream branch yet (e.g. GitHub). |
| `2 not deployed (production)` | Commits that are not on the deploy remote yet. |
| `no upstream` | The branch doesn't track a remote branch. |
| `not on production` | The branch was never pushed to the deploy remote. |

The **deploy remote** is the first remote that is not `origin` and not an HTTP(S) address,
e.g. a Plesk or Dokku git remote.

## Buttons

Every site with a local repository has two buttons. They show the number of files or commits
pending, and are greyed out when there is nothing to do:

- **Changes** (📄 3): the uncommitted files, see [Uncommitted changes](./changes).
- **Deploy** (🚀 2): pushes the commits to the deploy remote, see [Deploying](./deploy).

In a wide window each site is one compact row and the buttons show only the icon and the number;
hover over them for what they do. In a narrow window the site is a card with labeled buttons.

::: info Nothing is fetched
The app never contacts the remotes, so it never asks for an SSH passphrase. "Unpushed" and
"not deployed" compare with what this machine fetched or pushed last. A push from another machine
shows only after a `git fetch`.
:::

## The app bar

| Icon | |
|---|---|
| ☀️ 🌙 Ⓐ | The theme: light, dark or following the system. Each click switches to the next one. |
| ⟳ | Reads all versions and repositories again. |
| ⚙ | The settings, see [Managing sites](./settings). |

::: tip
The screenshots in this documentation follow its theme: switch it with the toggle at the top.
:::
