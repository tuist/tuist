import doczPluginNetlify from 'docz-plugin-netlify'

export default {
  title: 'Tuist Documentation',
  description:
    'Tuist is a tool that helps developers manage large Xcode projects by leveraging project generation. Moreover, it provides some tools to automate most common tasks, allowing developers to focus on building apps.',
  plugins: [doczPluginNetlify()],
  // https://github.com/pedronauck/docz/issues/793
  hashRouter: true,
  public: './public',
  htmlContext: {
    favicon: 'public/favicon.ico',
    head: {
      links: [
        {
          rel: 'stylesheet',
          href: '/public/swifty.css',
        },
        {
          rel: 'stylesheet',
          href:
            '//cdn.jsdelivr.net/npm/semantic-ui@2.4.2/dist/semantic.min.css',
        },
      ],
    },
  },
  menu: [
    'Getting started',
    'Project & Workspace',
    'Configuration',
    'Dependencies',
    'Setup',
    'Graph',
    'Managing versions',
    'Frequently asked questions',
    {
      name: 'Contributors',
      menu: [
        'Code reviews',
        'Tuist',
        'Galaxy',
        'Code of conduct',
        'Changelog guidelines',
        'Core team',
        'Zen',
      ],
    },
  ],
}
