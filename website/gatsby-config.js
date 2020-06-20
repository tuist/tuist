const remarkSlug = require('remark-slug')
const title = `Tuist - Xcode on steroids`
const siteUrl = 'https://tuist.io'

module.exports = {
  siteMetadata: {
    title: title,
    description: `Tuist is a tool that helps developers manage large Xcode projects by leveraging project generation. Moreover, it provides some tools to automate most common tasks, allowing developers to focus on building apps.`,
    siteUrl: siteUrl,
    discourseUrl: 'https://community.tuist.io',
    githubUrl: 'https://github.com/tuist',
    releasesUrl: 'https://github.com/tuist/tuist/releases',
    documentationUrl: 'https://docs.tuist.io/',
    slackUrl: 'http://slack.tuist.io/',
    twitterUrl: 'http://twitter.com/tuistio',
    editUrl: 'https://github.com/tuist/tuist/edit/master/website',
    contributeUrl: 'https://docs.tuist.io/contribution-1-getting-started',
    firstDocumentationPagePath: '/docs/usage/getting-started/',
    documentationCategories: [
      { folderName: 'usage', name: 'Usage' },
      { folderName: 'contribution', name: 'Contributors' },
    ],
  },
  plugins: [
    {
      resolve: `gatsby-theme-tailwindcss`,
      options: {
        postCssPlugins: [require('autoprefixer')],
      },
    },
    `gatsby-plugin-react-helmet`,
    {
      resolve: 'gatsby-plugin-next-seo',
      options: {
        titleTemplate: '%s | Tuist',
        openGraph: {
          type: 'website',
          title: title,
          locale: 'en_IE',
          url: siteUrl,
          site_name: title,
          images: [
            {
              url: `${siteUrl}/squared-logo.png`,
              width: 400,
              height: 400,
              alt: "Tuist's logo",
            },
          ],
          keywords: [
            `tuist`,
            `engineering`,
            `xcode`,
            `swift`,
            `project generation`,
            `xcode project generation`,
            `xcodeproj`,
            `xcodegen`,
            'ios',
            'uikit',
            'foundation',
            'tvos',
            'ios',
            'watchos',
            'objective-c',
            'swift package manager',
            'swift packages',
          ],
        },
        twitter: {
          site: '@tuistio',
          handle: '@tuistio',
          cardType: 'summary',
        },
      },
    },
    `gatsby-plugin-sharp`,
    `gatsby-plugin-sitemap`,
    `gatsby-plugin-offline`,
    `gatsby-plugin-theme-ui`,
    `gatsby-transformer-yaml`,
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
              return allMdx.edges.map((edge) => {
                const siteUrl = site.siteMetadata.siteUrl
                const postText = `
                <div style="margin-top=55px; font-style: italic;">(This is an article posted on tuist.io. You can read it online by <a href="${
                  siteUrl + edge.node.fields.slug
                }">clicking here</a>.)</div>
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
          `gatsby-remark-embedder`,
          `gatsby-remark-smartypants`,
          `gatsby-remark-copy-linked-files`,
          {
            resolve: `gatsby-remark-images`,
            options: {
              maxWidth: 590,
            },
          },
          'gatsby-remark-check-links',
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
    `gatsby-plugin-robots-txt`,
    {
      resolve: `gatsby-plugin-google-analytics`,
      options: {
        trackingId: 'UA-125584790-1',
      },
    },
    {
      resolve: `gatsby-plugin-purgecss`,
      options: {
        printRejected: true, // Print removed selectors and processed file names
        // develop: true, // Enable while using `gatsby develop`
        tailwind: true, // Enable tailwindcss support
        // whitelist: ['whitelist'], // Don't remove this selector
        // ignore: ['/ignored.css', 'prismjs/', 'docsearch.js/'], // Ignore files/folders
        // purgeOnly : ['components/', '/main.css', 'bootstrap/'], // Purge only these files/folders
      },
    },
  ],
}
