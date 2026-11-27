# Servers and new sites

## Servers

A server is reached through a **git remote of the same name** in every site's local repository,
e.g. `elkuku.dev` for a Plesk server and `kmyserver` for a [KMyServer](https://github.com/elkuku/KMyServer)
server. Manage them with the server switch in the app bar → **Servers…**:

- **Name** — shown in the switch, e.g. `New server`.
- **Git remote** — the remote the sites use for this server, e.g. `kmyserver`.
- **SSH host** and **Port** — only for KMyServer servers, to create sites from a template
  (e.g. `new.example.com`, or `localhost` and `2222` for the local test VM).
- **Server base URL** — the one address every project on this server builds on, e.g.
  `https://vm.localhost:8443` for the test VM or `https://example.com` for Plesk. A project stores
  only a subdomain on each [environment](./settings#environments); the app derives
  `https://<subdomain>.<server host>` from it. Older settings with a domain suffix and site port keep
  working; editing the server converts them into this one field.

The servers are saved in `preferences.json`, next to the theme.

## Switching the server

The switch in the app bar picks the server whose status is shown beside the projects:

- **Own remotes** — no server status pane and no `/system/info/` requests: the project rows show only
  git status and the versions read from the local repository. Every project uses its own deploy
  remote.
- **A server** — the versions of a project with an environment on that server are compared with the
  address derived from the server's base URL and the project's subdomain. This works for a
  non-KMyServer such as Plesk too. A KMyServer also shows its health report beside the project list,
  matches its sites to the projects, and keeps the active server's **Releases** and **Roll back**
  buttons in the compact project rows.

A project's deploy remote comes from its [environments](./settings#environments): the target for
the active server wins, otherwise the first target is used. A target with **`-`** as remote never
deploys. The 🚀 button is greyed out when nothing can be deployed; add the remote to the repository
if needed.

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
- When a KMyServer is selected, a project that is **not on that server yet** gets a
  **Deploy to `<server>`…** button in its expanded details. It is not shown for other servers or
  for a project that already has an environment there. It asks which site name, subdomain and git
  template to use (prefilled from the project and its remotes), shows the address derived from that
  server's base URL, runs `site-add` as root, adds the server remote locally and then uses the usual
  Deploy dialog to push the branch. The chosen subdomain/name is saved back into the project's
  environment.

  If the project's local compose files or `.env` show a database, **Create PostgreSQL database**
  is preselected; you can override it. The dialog then lists the server's dated backup sets
  (`site-db-backups list`) and lets you pick a `pg-*.dump` to import into the new database before
  the push (`site-db-import`). The import first clears objects the template deploy created, so
  the dump's schema and data are restored. The newest dump is selected by default; **No backup
  (empty database)** is also available. KMyServer only offers PostgreSQL — a MariaDB project needs
  a separate migration. A failed import stops the flow: the site and DB were created, but nothing
  is deployed and the error is shown. No database password is ever stored in the app.

The status pane itself keeps only host-level information and actions. It never runs a free-form
command — every button sends a fixed argument list over SSH, shows the command, streams the output
and shows the exit code. A non-zero exit is always visible.

- **Server:** refresh the report, run a backup, send a test mail, or open the add-site wizard already
  switched to **New on KMyServer** with this server selected.
- **Each site:** the actions above, from the site's card in the project list.

**Remove site** first shows a dry run that changes nothing. To go on you must type the site name;
dropping the database also needs a second confirmation. The final backup is made by the server
before anything is removed.

## New site from a template

The single ＋ **Add site** button in the top bar opens one wizard with a switch: **Existing project**
registers a project you already have locally, **New on KMyServer** creates one on a server. The
server pane's **New site…** opens the same wizard on the template step. Creating a new site means:

1. **On the server** — `site-add <name> --domain <host> --template <template>` runs as root over
   SSH: user, database, PHP pool, Caddy site, and the template is deployed at once. `<host>` is the
   subdomain prefixed to this server's base URL host. Its steps show in the log.
2. **Locally** — the site's repository is cloned into `<folder>/<name>`, with the server's remote
   name (e.g. `kmyserver`) instead of `origin`.
3. **GitHub** — `gh repo create <name> --private|--public --source <folder>/<name> --remote origin --push`
   makes a repository with the GitHub CLI and pushes the code there. **Private repository** is
   checked by default; uncheck it to create a public repository. The project's full GitHub URL is
   entered in the wizard even when this step creates it.

Then **Add to the list** adds the site with its display name, local repository, GitHub URL and one
environment on the server.

- **Templates:** *Symfony starter* (github.com/elkuku/symfony-starter), or any public https git URL,
  optionally with a branch: `https://github.com/symfony/demo.git#main`.
- **Site address:** derived from the server's base URL and the subdomain, e.g.
  `https://shop.localhost:8443` on the test VM; the helper text below the field shows it.
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
