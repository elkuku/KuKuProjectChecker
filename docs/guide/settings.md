# Managing sites

The gear icon opens the list of sites. Each site has:

- **Name** (optional): the title in the site list. Without a name, the host of the URL is used.
- **Site URL**: the address of the site, e.g. `https://shop.example.com`.
- **Local repository** (optional): the folder of the project's git repository, e.g. `~/repos/shop`.
  With it, the site list shows the repository's status, and the [changes](./changes) and the
  [Open in …](./open-in) apps become available.

![The settings](../screenshots/05_settings-dark.png){.theme-dark}
![The settings](../screenshots/05_settings-light.png){.theme-light}

- **Open or close** a site with a click on its header or the arrow on the right. Closed, it shows
  only its name, address and repository; the button next to **Add site** opens or closes all of them.
- **Add a site** with **Add site**.
- **Reorder** the sites by dragging them by the handle (⋮⋮) on the left. The site list uses the same order.
- **Remove** a site with the trash can; **Undo** in the message at the bottom brings it back.

Changes are **saved on their own**, a moment after you stop typing, and again when you leave the
settings; the top bar shows *Saved*. As long as a site has no valid address (`https://…`), nothing
is saved and the address field shows what is wrong. Leaving then asks whether to fix the address or
leave without that site. A new site you leave empty is dropped.
