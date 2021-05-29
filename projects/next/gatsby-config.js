const title = 'Tuist'
const siteUrl = 'https://tuist.io'
const twitterHandle = 'tuistio'
const description =
  'Boost your productivity working with Xcode projects. Focus on building features while Tuist simplifies your projects.'

module.exports = {
  siteMetadata: {
    title: title,
    siteUrl: siteUrl,
    twitterHandle: twitterHandle,
    links: {
      slack: 'https://slack.tuist.io',
      releases: 'https://github.com/tuist/tuist/releases',
      githubRepository: 'https://github.com/tuist/tuist',
      githubOrganization: 'https://github.com/tuist',
    },
  },
  plugins: [
    'gatsby-plugin-sharp',
    'gatsby-plugin-react-helmet',
    'gatsby-plugin-sitemap',
    'gatsby-plugin-offline',
    {
      resolve: 'gatsby-plugin-web-font-loader',
      options: {
        custom: {
          families: ['ModernEra', 'ModernEraMono'],
          urls: ['/fonts/fonts.css'],
        },
      },
    },
    {
      resolve: 'gatsby-plugin-manifest',
      options: {
        icon: 'src/images/logo.png',
      },
    },
    'gatsby-plugin-mdx',
    'gatsby-transformer-sharp',
    {
      resolve: 'gatsby-source-filesystem',
      options: {
        name: 'images',
        path: './src/images/',
      },
      __key: 'images',
    },
    {
      resolve: 'gatsby-source-filesystem',
      options: {
        name: 'pages',
        path: './src/pages/',
      },
      __key: 'pages',
    },
    {
      resolve: `gatsby-plugin-typescript`,
      options: {
        isTSX: true,
        jsxPragma: `jsx`,
        allExtensions: true,
      },
    },
    {
      resolve: 'gatsby-plugin-next-seo',
      options: {
        titleTemplate: `${title} | %s`,
        title: `${title} - Boost your productivity`,
        description: description,
        openGraph: {
          type: 'website',
          locale: 'en_IE',
          url: siteUrl,
          site_name: title,
        },
        twitter: {
          handle: `${twitterHandle}`,
          site: '@site',
          cardType: 'summary',
        },
      },
    },
  ],
}
