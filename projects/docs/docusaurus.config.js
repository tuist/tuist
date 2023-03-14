/** @type {import('@docusaurus/types').DocusaurusConfig} */
const remarkEmoji = require('remark-emoji')
const remarkExternalLinks = require('remark-external-links')

module.exports = {
  title: 'Tuist Documentation',
  tagline: 'Documentation about how to use and contribute to the tool.',
  url: 'https://docs.tuist.io',
  baseUrl: '/',
  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',
  favicon: 'img/favicon.ico',
  organizationName: 'tuist',
  projectName: 'tuist',
  customFields: {
    defaultDocsLandingPage: 'tutorial/get-started',
  },
  themeConfig: {
    prism: {
      additionalLanguages: ['yaml', 'swift', 'ruby'],
      theme: require('prism-react-renderer/themes/dracula'),
    },
    algolia: {
      appId: 'TKP20U9DH0',
      apiKey: '927a1ebcb792b7e9a652c185c3e10bae',
      indexName: process.env.ALGOLIA_INDEX_NAME || 'dev',
      contextualSearch: true,
      searchParameters: {},
    },
    navbar: {
      title: 'Tuist',
      logo: {
        alt: 'Tuist Logo',
        src: 'img/logo.svg',
      },
      items: [
        {
          type: 'docsVersionDropdown',
          position: 'right',
        },
        {
          href: 'https://github.com/tuist/tuist',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'Getting Started',
              to: '/',
            },
          ],
        },
        {
          title: 'Community',
          items: [
            {
              label: 'GitHub Discussions',
              href: 'https://stackoverflow.com/questions/tagged/docusaurus',
            },
            {
              label: 'Slack',
              href: 'https://join.slack.com/t/tuistapp/shared_invite/zt-1lqw355mp-zElRwLeoZ2EQsgGEkyaFgg',
            },
            {
              label: 'Twitter',
              href: 'https://twitter.com/tuistio',
            },
          ],
        },
        {
          title: 'More',
          items: [
            {
              label: 'tuist.io',
              to: 'https://tuist.io',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Tuist, Inc. Built with Docusaurus.`,
    },
  },
  plugins: [],
  presets: [
    [
      '@docusaurus/preset-classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: require.resolve('./sidebars.js'),
          editUrl: 'https://github.com/tuist/tuist/blob/main/projects/docs/',
          remarkPlugins: [remarkEmoji, remarkExternalLinks],
          lastVersion: 'current',
          versions: {
            current: {
              label: '3.x',
            },
            2: {
              label: '2.x',
            },
            1: {
              label: '1.x',
            },
          },
        },
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      },
    ],
  ],
}
