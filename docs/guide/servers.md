# Servers and new sites

## Servers

A server is reached through a **git remote of the same name** in every site's local repository,
e.g. `elkuku.dev` for a Plesk server and `kmyserver` for a [KMyServer](https://github.com/elkuku/KMyServer)
server. Manage them with the server switch in the app bar → **Servers…**:

- **Name** — shown in the switch, e.g. `New server`.
- **Git remote** — the remote the sites use for this server, e.g. `kmyserver`.
- **SSH host** and **Port** — only for KMyServer servers, to create sites from a template
  (e.g. `new.example.com`, or `localhost` and `2222` for the local test VM).
- **HTTPS port of the sites** — if not 443, e.g. `8443` for the local test VM; new sites get
  `https://<domain>:<port>` as their address.
- **Domain suffix** — e.g. `localhost` or `kmy.example.com`: a new site on this server is suggested
  as `<site name>.<domainSuffix>`. Leave it empty for servers where sites use their own domain
  (local Symfony, Plesk).

The servers are saved in `preferences.json`, next to the theme.

## Switching the server

The switch in the app bar picks the server whose status is shown beside the projects:

- **Own remotes** — no server status pane; every project uses its own deploy remote.
- **A KMyServer** — its health report appears beside the project list, and its sites are matched
  to the projects. The active server's **Releases** and **Roll back** buttons stay in the compact
  project rows.

A project's deploy remote comes from its [environments](./settings#environments): the target for
the active server wins, otherwise the first target is used. A project still using the older single
site form keeps the previous behaviour: the active server's remote is used for it. A target with
**`-`** as remote never deploys. The 🚀 button is greyed out when nothing can be deployed; add the
remote to the repository if needed.

**Roll back** is offered on a row when a KMyServer reports about one of its environments.

## Server status and actions

When a KMyServer server is selected, its health report always appears beside the project list; the
Linux window has a minimum width so both panes fit. The report feeds the project cards, not a
second site list in the status pane:

- A project that is on a server gets **HTTP**, **deploy** and **CRITICAL** badges for each matching
  environment (matched by server and address or site name). Its row has **Releases** and
  **Roll back** buttons; the expanded details add the four logs and **Remove site**.
- A server site without a local project appears at the end of the list as a temporary row, marked
  *not in the projects* when expanded. Nothing is saved for it; it disappears when another server
  is selected or the site is removed. Its buttons offer the same server actions.
- A project that is not on a server gets a **Deploy to `<server>`…** button in its expanded details.
  It asks which site name, domain and git template to use (prefilled from the project, that
  server's domain suffix and its remotes), runs `site-add` as root, adds the server remote locally
  and then uses the usual Deploy dialog to push the branch. The chosen domain/name is saved back
  into the project's environment.

The status pane itself keeps only host-level information and actions. It never runs a free-form
command — every button sends a fixed argument list over SSH, shows the command, streams the output
and shows the exit code. A non-zero exit is always visible.

- **Server:** refresh the report, run a backup, send a test mail, or open the **New site…** wizard.
- **Each site:** the actions above, from the site's card in the project list.

**Remove site** first shows a dry run that changes nothing. To go on you must type the site name;
dropping the database also needs a second confirmation. The final backup is made by the server
before anything is removed.

## New site from a template

The ➕ button with the box (**New site from a template**) creates a complete site on a KMyServer
server:

1. **On the server** — `site-add <name> --domain <domain> --template <template>` runs as root over
   SSH: user, database, PHP pool, Caddy site, and the template is deployed at once. Its steps show
   in the log.
2. **Locally** — the site's repository is cloned into `<folder>/<name>`, with the server's remote
   name (e.g. `kmyserver`) instead of `origin`.
3. **GitHub** (optional) — `gh repo create <name> --private --source <folder>/<name> --remote origin --push`
   makes a private repository with the GitHub CLI and pushes the code there.

Then **Add to the list** adds the site with its address and local repository.

- **Templates:** *Symfony starter* (github.com/elkuku/symfony-starter), or any public https git URL,
  optionally with a branch: `https://github.com/symfony/demo.git#main`.
- **Site address:** follows the domain and the server's HTTPS port (`https://<domain>`, on the
  test VM `https://<domain>:8443`); change it when the site is reached differently.
- The local folder must not exist yet.

::: info Local certificates
Sites on `localhost`, `*.localhost` or `127.x.x.x` (the test VM, the Symfony CLI) often use their
own certificate authority. The app accepts their certificates; for every other address the
certificate must be valid.
:::

::: tip Requirements
SSH access as **root** to the server (for `site-add`) and as the site user (for cloning; site-add
gives it the same keys as root). For the GitHub step the [GitHub CLI](https://cli.github.com) must be
installed and logged in (`gh auth login`).
:::
