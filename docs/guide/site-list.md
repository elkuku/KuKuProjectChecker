# The site list

Each project is one compact row with its name, its address, the buttons you need most and, when a
KMyServer reports about it, its server badges. Versions and repository details are hidden until you
expand the row; the server status always stays beside the list.

![The site list](../screenshots/01_sites-dark.png){.theme-dark}
![The site list](../screenshots/01_sites-light.png){.theme-light}

![Compact rows](../screenshots/09_compact_rows-dark.png){.theme-dark}
![Compact rows](../screenshots/09_compact_rows-light.png){.theme-light}

Tap **Show details** (▾) to see the versions, the repository status and the rest of the actions:

![Expanded row](../screenshots/10_expanded_row-dark.png){.theme-dark}
![Expanded row](../screenshots/10_expanded_row-light.png){.theme-light}

## Versions

- **PHP** and **Symfony**: the versions the site reports, see [Site requirements](./site-requirements).
- **Database** (🗄 MariaDB 12.3.4): the database server, if the site tells it.
- **Last deploy** (🚀 3h ago): when the site was last deployed, if it tells it. Orange if that deploy
  finished with errors, red if it didn't finish. Hover for the date.
- **Not reachable**: the site didn't answer, or it has no `/system/info/` endpoint.
- **Dev site** (🧪 dev 12m), if the site has a [dev site URL](./settings): when the dev site last
  deployed itself. Hover for its versions and dates.

| Dev badge | Meaning |
|---|---|
| 🧪 dev 12m | The last deploy went fine and is newer than the newest commit of the upstream branch (e.g. `origin/master`) |
| 🧪 dev behind (orange) | The upstream branch has a newer commit than the last deploy: the webhook didn't fire, or the deploy is still running |
| 🧪 dev errors (orange) / dev unfinished (red) | The last deploy finished with errors / didn't finish |
| 🧪 dev offline (red) | The dev site didn't answer |

The upstream branch is compared as of your last fetch or push, like the repository status below.

### Live and local versions

If a site has a local repository, the app compares its versions with the ones the project uses on
this machine. A badge that differs turns **orange** with ⇄; hover over it to see both versions.

| Badge | Local version from | Compared |
|---|---|---|
| PHP | the `php` on your PATH | major and minor, e.g. 8.5 |
| Symfony | `symfony/http-kernel` in `composer.lock` | the full version, so an update that is not deployed yet shows |
| Database | the database image in the docker compose files, e.g. `mariadb:12.3` or `postgres:16-alpine` | the platform, and the version as far as the image tag gives it: `16` matches 16.4 |

The Symfony project doesn't have to be at the top of the repository: if the repository has no
`composer.json`, the app uses the first folder directly inside it that has one, e.g. `web/` in a
repository that also holds an Android app. The compose files are read from both places.

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

The **deploy remote** is the one chosen for the site in its **Edit…** dialog; on **Automatic**,
the first remote that is not `origin`, not an HTTP(S) address and not on a code host like GitHub,
e.g. a Plesk or Dokku git remote. See [Deploying](./deploy).

## Each project

- **⋮⋮** on the left: drag the project to another place in the list.
- **▾ / ▴**: show or hide the details (versions, repository status and the remaining actions).
- **✏️ Edit…** and **▤ Environments…**: manage the project and its environments
  ([Managing sites](./settings), [Servers](./servers)).
- **▾ Open in…**: only open actions — the site or repository in the browser and other apps,
  see [Open in …](./open-in). Management actions are buttons, never menu entries.
- When a KMyServer knows the project, **Releases** and **Roll back** are buttons in the row too;
  logs, removal and the actions of other servers are in the expanded details.

## Buttons

Every project with a local repository has two buttons. They show the number of files or commits
pending, and are greyed out when there is nothing to do:

- **Changes** (📄 3): the uncommitted files, see [Uncommitted changes](./changes).
- **Deploy** (🚀 2): pushes the commits to the deploy remote, see [Deploying](./deploy).

Collapsed rows show only their icons and numbers; hover over them for the full text. Expanded
details use labeled buttons.

::: info Nothing is fetched
The app never contacts the remotes, so it never asks for an SSH passphrase. "Unpushed" and
"not deployed" compare with what this machine fetched or pushed last. A push from another machine
shows only after a `git fetch`.
:::

## The app bar

| Icon | |
|---|---|
| ＋ | Adds a site, see [Managing sites](./settings). |
| ☀️ 🌙 Ⓐ | The theme: light, dark or following the system. Each click switches to the next one. |
| ⟳ | Reads all versions and repositories again. |

::: tip
The screenshots in this documentation follow its theme: switch it with the toggle at the top.
:::
