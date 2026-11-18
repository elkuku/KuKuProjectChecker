import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'KuKu Project Checker',
  description: 'Keep an eye on your Symfony sites and their local git repositories',
  base: '/KuKuProjectChecker/',

  head: [['link', { rel: 'icon', href: '/KuKuProjectChecker/logo.svg' }]],

  // The screenshot generator lives next to the images; it is not a page.
  srcExclude: ['screenshots/**'],

  themeConfig: {
    logo: '/logo.svg',

    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'Site requirements', link: '/guide/site-requirements' },
      { text: 'Development', link: '/development' },
    ],

    sidebar: [
      {
        text: 'Getting Started',
        items: [
          { text: 'Overview', link: '/' },
          { text: 'Installation', link: '/guide/getting-started' },
          { text: 'Site requirements', link: '/guide/site-requirements' },
        ],
      },
      {
        text: 'Using the app',
        items: [
          { text: 'The site list', link: '/guide/site-list' },
          { text: 'Managing sites', link: '/guide/settings' },
          { text: 'Open in …', link: '/guide/open-in' },
          { text: 'Uncommitted changes', link: '/guide/changes' },
        ],
      },
      {
        text: 'Development',
        items: [{ text: 'Development guide', link: '/development' }],
      },
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/elkuku/KuKuProjectChecker' },
    ],

    editLink: {
      pattern: 'https://github.com/elkuku/KuKuProjectChecker/edit/master/docs/:path',
    },

    footer: {
      message: 'Made with Dart and Flutter.',
    },

    search: {
      provider: 'local',
    },
  },
})
