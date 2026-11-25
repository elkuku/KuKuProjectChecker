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

The servers are saved in `preferences.json`, next to the theme.

## Switching the server

The switch in the app bar says where the sites deploy:

- **Each site's own deploy remote** — the default: every site uses the remote chosen in its
  **Edit…** dialog (or the automatic choice), see [Deploying](./deploy).
- **A server** — every site deploys to that server's remote, e.g. all to the new server while
  moving off Plesk, or all to the test VM. A site without that remote can't deploy (its 🚀 button
  is greyed out); add the remote to its repository. Sites set to **No deploys** stay that way.

**Roll back…** follows the switch: it is offered when the active deploy remote is a KMyServer
site repository.

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
