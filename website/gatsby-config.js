const remarkSlug = require('remark-slug')

module.exports = {
  siteMetadata: {
    title: `Tuist - Xcode on steroids`,
    description: `Tuist is a tool that helps developers manage large Xcode projects by leveraging
    project generation. Moreover, it provides some tools to automate most common tasks, allowing
    developers to focus on building apps.`,
    siteUrl: 'https://tuist.io',
    githubUrl: 'https://github.com/tuist',
    releasesUrl: 'https://github.com/tuist/tuist/releases',
    documentationUrl: 'https://docs.tuist.io/',
    slackUrl: 'http://slack.tuist.io/',
    editUrl: 'https://github.com/tuist/website/edit/master',
    contributeUrl: 'https://docs.tuist.io/contribution-1-getting-started',
    firstDocumentationPagePath: '/docs/usage/getting-started/',
    documentationCategories: [
      { folderName: 'usage', name: 'Usage' },
      { folderName: 'contribution', name: 'Contributors' },
    ],
  },
  plugins: [
    `gatsby-plugin-sitemap`,
    `gatsby-plugin-offline`,
    `gatsby-plugin-theme-ui`,
    `gatsby-transformer-yaml`,
    `gatsby-plugin-react-helmet`,
    {
      resolve: `gatsby-source-filesystem`,
      name: 'data',
      options: {
        path: `${__dirname}/data`,
      },
    },
    {
      resolve: `gatsby-source-filesystem`,
      options: {
        name: `markdown`,
        path: `${__dirname}/markdown/`,
      },
    },
    {
      resolve: 'gatsby-plugin-react-svg',
      options: {
        rule: {
          include: /assets/,
        },
      },
    },
    {
      resolve: `gatsby-plugin-manifest`,
      options: {
        name: `Tuist`,
        short_name: `Tuist`,
        start_url: `/`,
        background_color: `#12344F`,
        theme_color: `#12344F`,
        display: `minimal-ui`,
        icon: `static/favicon.png`, // This path is relative to the root of the site.
      },
    },
    {
      resolve: `gatsby-plugin-favicon`,
      options: {
        logo: './static/favicon.png',
        appName: 'Tuist',
        appDescription:
          'Bootstrap, maintain, and interact with Xcode projects at any scale',
        developerName: 'Pedro Piñera',
        developerURL: 'https://ppinera.es',
        dir: 'auto',
        lang: 'en-US',
        background: '#12344F',
        theme_color: '#12344F',
        display: 'standalone',
        orientation: 'any',
        version: '1.0',
        start_url: '/',
        icons: {
          android: true,
          appleIcon: true,
          appleStartup: true,
          coast: false,
          favicons: true,
          firefox: true,
          opengraph: false,
          twitter: true,
          yandex: false,
          windows: false,
        },
      },
    },
    {
      resolve: `gatsby-plugin-feed`,
      options: {
        query: `
          {
            site {
              siteMetadata {
                title
                description
                siteUrl
                site_url: siteUrl
              }
            }
          }
        `,
        feeds: [
          {
            serialize: ({ query: { site, allMdx } }) => {
              return allMdx.edges.map(edge => {
                const siteUrl = site.siteMetadata.siteUrl
                const postText = `
                <div style="margin-top=55px; font-style: italic;">(This is an article posted on tuist.io. You can read it online by <a href="${siteUrl +
                  edge.node.fields.slug}">clicking here</a>.)</div>
              `

                let html = edge.node.html
                html = html
                  .replace(/href="\//g, `href="${siteUrl}/`)
                  .replace(/src="\//g, `src="${siteUrl}/`)
                  .replace(/"\/static\//g, `"${siteUrl}/static/`)
                  .replace(/,\s*\/static\//g, `,${siteUrl}/static/`)
                return Object.assign({}, edge.node.frontmatter, {
                  description: edge.node.frontmatter.excerpt,
                  date: edge.node.fields.date,
                  url: site.siteMetadata.siteUrl + edge.node.fields.slug,
                  guid: site.siteMetadata.siteUrl + edge.node.fields.slug,
                  custom_elements: [{ 'content:encoded': html + postText }],
                })
              })
            },
            query: `
              {
                allMdx(
                  limit: 1000,
                  filter: { fields: { type: { eq: "blog-post" } } },
                  sort: { order: DESC, fields: [fields___date] }
                ) {
                  edges {
                    node {
                      html
                      fields { 
                        slug 
                        date  
                      }
                      frontmatter {
                        title
                        excerpt
                      }
                    }
                  }
                }
              }
            `,
            title: "Tuist's Blog RSS Feed",
            output: '/feed.xml',
          },
        ],
      },
    },
    {
      resolve: `gatsby-plugin-mdx`,
      options: {
        extensions: ['.mdx', '.md'],
        remarkPlugins: [remarkSlug],
        gatsbyRemarkPlugins: [
          `gatsby-remark-smartypants`,
          {
            resolve: `gatsby-remark-social-cards`,
            options: {
              type: 'blog-post',
              title: {
                field: 'title',
                font: 'DejaVuSansCondensed',
                color: 'white',
                size: 48,
                style: 'bold',
                x: null,
                y: null,
              },
              meta: {
                parts: ['Tuist'],
                font: 'DejaVuSansCondensed',
                color: 'white',
                size: 24,
                style: 'normal',
                x: null,
                y: null,
              },
              background: '#17223b',
              xMargin: 24,
              yMargin: 24,
            },
          },
        ],
      },
    },
    {
      resolve: `gatsby-plugin-netlify`,
      options: {
        headers: {}, // option to add more headers. `Link` headers are transformed by the below criteria
        allPageHeaders: [], // option to add headers for all pages. `Link` headers are transformed by the below criteria
        mergeSecurityHeaders: true, // boolean to turn off the default security headers
        mergeLinkHeaders: true, // boolean to turn off the default gatsby js headers
        mergeCachingHeaders: true, // boolean to turn off the default caching headers
        transformHeaders: (headers, path) => headers, // optional transform for manipulating headers under each path (e.g.sorting), etc.
        generateMatchPathRewrites: true, // boolean to turn off automatic creation of redirect rules for client only paths
      },
    },
    'gatsby-plugin-meta-redirect',
  ],
}
