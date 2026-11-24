# Managing sites

The sites are managed right in the site list. Each site has:

- **Name** (optional): the title in the site list. Without a name, the host of the URL is used.
- **Site URL**: the address of the site, e.g. `https://shop.example.com`.
- **Local repository** (optional): the folder of the project's git repository, e.g. `~/repos/shop`.
  Type it, or choose it with 📂 next to the field; a folder in your home folder is written with `~`.
  With it, the site list shows the repository's status, and the [changes](./changes) and the
  [Open in …](./open-in) apps become available.
- **Deploy remote** (with a local repository): the git remote that [Deploy](./deploy) pushes to.
  **Automatic** (the default) shows the remote the app picks; choose one of the repository's
  remotes to set it yourself, or **No deploys** for a site that isn't deployed from the app.

![Editing a site](../screenshots/05_edit_site-dark.png){.theme-dark}
![Editing a site](../screenshots/05_edit_site-light.png){.theme-light}

- **Add a site** with ＋ in the top bar (or **Add site** while the list is empty).
- **Edit a site** with **Edit…** in its ⋮ menu.
- **Remove a site** with **Remove** in its ⋮ menu; **Undo** in the message at the bottom brings it back.
- **Reorder** the sites by dragging them by the handle (⋮⋮) on the left.

A site needs a full address (`https://…`); the dialog shows what is wrong otherwise. Every change is
saved right away, and only the site you added or edited is read again.
