/** @type {import('@docusaurus/types').DocusaurusConfig} */
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
    defaultDocsLandingPage: 'getting-started',
  },
  themeConfig: {
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
          to: '/docs/getting-started',
          activeBasePath: 'docs',
          label: 'Docs',
          position: 'left',
        },
        { to: 'blog', label: 'Blog', position: 'left' },
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
              to: 'docs/',
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
  plugins: [
    [
      '@docusaurus/plugin-sitemap',
      {
        changefreq: 'weekly',
        priority: 0.5,
        trailingSlash: false,
      },
    ],
  ],
  presets: [
    [
      '@docusaurus/preset-classic',
      {
        docs: {
          sidebarPath: require.resolve('./sidebars.js'),
          editUrl: 'https://github.com/tuist/tuist/blob/main/projects/docs/',
        },
        blog: {
          showReadingTime: true,
          editUrl:
            'https://github.com/tuist/tuist/blob/main/projects/docs/blog',
        },
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      },
    ],
  ],
}
