import doczPluginNetlify from 'docz-plugin-netlify'
import prismTheme from 'prism-react-renderer/themes/nightOwl'

export default {
  title: 'Tuist Documentation',
  description:
    'Tuist is a tool that helps developers manage large Xcode projects by leveraging project generation. Moreover, it provides some tools to automate most common tasks, allowing developers to focus on building apps.',
  plugins: [doczPluginNetlify()],
  // https://github.com/pedronauck/docz/issues/793
  hashRouter: true,
  public: './public',
  themeConfig: {
    prismTheme: prismTheme,
  },
  menu: [
    'Getting started',
    'Project & Workspace',
    'Project description helpers',
    'Configuration',
    'Dependencies',
    'Set up the environment',
    'Editing your projects',
    'Dependencies graph',
    'Managing versions',
    'Frequently asked questions',
    {
      name: 'Contributors',
      menu: [
        'Code reviews',
        'Tuist',
        'Code of conduct',
        'Changelog guidelines',
        'Core team',
        'Zen',
      ],
    },
  ],
}
