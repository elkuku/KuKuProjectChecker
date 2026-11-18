---
layout: home

hero:
  name: KuKu Project Checker
  text: Your Symfony sites at a glance
  tagline: PHP and Symfony versions of every site, and what is not yet committed, pushed or deployed in its local repository.
  image:
    src: /logo.svg
    alt: KuKu Project Checker
  actions:
    - theme: brand
      text: Get started
      link: /guide/getting-started
    - theme: alt
      text: View on GitHub
      link: https://github.com/elkuku/KuKuProjectChecker

features:
  - icon: 🌐
    title: Versions of every site
    details: Reads the PHP and Symfony versions from each site's /system/info/ endpoint and flags sites that are not reachable.
  - icon: 🌿
    title: Local repository status
    details: Shows the branch and how many files are uncommitted, how many commits are unpushed and how many are not yet deployed.
  - icon: 🔍
    title: Changes and diffs
    details: Lists the uncommitted files of a project and shows the diff of each file, colored.
  - icon: 🚀
    title: Open in …
    details: Opens a project in the browser, the file manager, a terminal, PhpStorm, VS Code, Kate or gitk.
---

<div class="screens">

![The site list](./screenshots/01_sites-dark.png){.theme-dark}
![The site list](./screenshots/01_sites-light.png){.theme-light}
![The diff of a file](./screenshots/04_diff-dark.png){.theme-dark}
![The diff of a file](./screenshots/04_diff-light.png){.theme-light}

</div>
