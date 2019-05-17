export default {
  title: 'Tuist Documentation',
  description:
    'Tuist is a tool that helps developers manage large Xcode projects by leveraging project generation. Moreover, it provides some tools to automate most common tasks, allowing developers to focus on building apps.',
  themeConfig: {
    codemirrorTheme: 'dracula',
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
  },
  public: './public',
  htmlContext: {
    favicon: 'public/favicon.ico',
    head: {
      links: [
        {
          rel: 'stylesheet',
          href: 'https://codemirror.net/theme/dracula.css',
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
    'Manifest format',
    'Dependencies',
    'Up tasks',
    'Managing versions',
    'Frequently asked questions',
    {
      name: 'Contributors',
      menu: [
        'Getting started',
        'Code of conduct',
        'Changelog guidelines',
        'Core team',
        'Zen',
      ],
    },
  ],
}
