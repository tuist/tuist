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
    defaultDocsLandingPage: 'contributors/get-started',
  },
  themeConfig: {
    prism: {
      additionalLanguages: ['swift', 'ruby'],
      theme: require('prism-react-renderer/themes/dracula'),
    },
    algolia: {
      apiKey: process.env.ALGOLIA_API_KEY || 'dev',
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
              href:
                'https://join.slack.com/t/tuistapp/shared_invite/zt-g38gajhj-D6LLakrPnVCy4sLm24KxaQ',
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
        },
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      },
    ],
  ],
}
