import doczPluginNetlify from 'docz-plugin-netlify'

export default {
  title: 'Tuist Documentation',
  description:
    'Tuist is a tool that helps developers manage large Xcode projects by leveraging project generation. Moreover, it provides some tools to automate most common tasks, allowing developers to focus on building apps.',
  plugins: [doczPluginNetlify()],
  // https://github.com/pedronauck/docz/issues/793
  base: '/docs/',
  hashRouter: true,
  themeConfig: {
    codemirrorTheme: 'swifty',
    colors: {
      blue: '#3495E8',
      darkBlue: '#12344F',
      lightGray: '#F8F8F8',
      gray: '#A3A3A3',
      purple: '#7768AF',
      darkPurple: '#52428E',
      green: '#3EB270',
      darkGreen: '#207E49',
      yellow: '#FFC107',
      primary: '#3495E8',
      link: 'green',
      sidebarHighlight: 'purple',
    },
    logo: {
      src: '/public/logo.png',
      width: 100,
    },
    styles: {
      body: `
        font-family: -apple-system, system-ui, "Helvetica Neue", Helvetica, Arial, Verdana, sans-serif;
      `,
      code: `
        font-size: 13px;
        font-family: Menlo, Consolas, Monaco, "Courier New", monospace, serif;
        background-color: white;
      `,
    },
  },
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
