const { createFilePath } = require(`gatsby-source-filesystem`)
const path = require(`path`)

exports.onCreateNode = ({ node, getNode, actions }) => {
  const { createNodeField, createRedirect } = actions

  // Redirects
  createRedirect({
    fromPath: '/docs',
    toPath: '/docs/usage/get-started/',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/docs/usage/getting-started/',
    toPath: '/docs/usage/get-started/',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/docs/usage/projectswift/',
    toPath: '/docs/usage/project-description/',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/docs/architectures/microfeatures/',
    toPath: '/docs/usage/microfeatures/',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/docs/usage/app-extensions/',
    toPath: '/docs/examples/app-extensions/',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/docs/usage/microfeatures/',
    toPath: '/docs/building-at-scale/microfeatures/',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/docs/usage/caching/',
    toPath: '/docs/building-at-scale/caching/',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/docs/usage/best-practices/',
    toPath: '/docs/building-at-scale/best-practices/',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/docs/usage/dependencies/',
    toPath: '/docs/dependencies/local/',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/docs/usage/third-party-dependencies/',
    toPath: '/docs/dependencies/third-party/',
    isPermanent: true,
  })

  // Redirects to docs.tuist.io
  createRedirect({
    fromPath: '/building-at-scale/best-practices',
    toPath: 'https://docs.tuist.io/building-at-scale/best-practices',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/building-at-scale/caching',
    toPath: 'https://docs.tuist.io/building-at-scale/caching',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/building-at-scale/microfeatures',
    toPath: 'https://docs.tuist.io/building-at-scale/microfeatures',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/autocompletion',
    toPath: 'https://docs.tuist.io/guides/shell-autocompletion',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/build',
    toPath: 'https://docs.tuist.io/commands/build',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/cache',
    toPath: 'https://docs.tuist.io/commands/cache',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/clean',
    toPath: 'https://docs.tuist.io/commands/clean',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/dependencies',
    toPath: 'https://docs.tuist.io/commands/dependencies',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/doc',
    toPath: 'https://docs.tuist.io/commands/documentation',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/edit',
    toPath: 'https://docs.tuist.io/commands/edit',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/generate',
    toPath: 'https://docs.tuist.io/commands/generate',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/graph',
    toPath: 'https://docs.tuist.io/commands/graph',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/linting',
    toPath: 'https://docs.tuist.io/commands/linting',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/migration',
    toPath: 'https://docs.tuist.io/commands/migration',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/scaffold',
    toPath: 'https://docs.tuist.io/commands/scaffold',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/secrets',
    toPath: 'https://docs.tuist.io/commands/secrets',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/signing',
    toPath: 'https://docs.tuist.io/commands/signing',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/test',
    toPath: 'https://docs.tuist.io/commands/test',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/commands/up',
    toPath: 'https://docs.tuist.io/commands/up',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/contribution/analytics-events',
    toPath: 'https://docs.tuist.io/contributors/analytics-events',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/contribution/architecture',
    toPath: 'https://docs.tuist.io/contributors/architecture',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/contribution/code-reviews',
    toPath: 'https://docs.tuist.io/contributors/code-reviews',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/contribution/fourier',
    toPath: 'https://docs.tuist.io/contributors/fourier',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/contribution/generation-pipeline',
    toPath: 'https://docs.tuist.io/contributors/generation-pipeline',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/contribution/get-started',
    toPath: 'https://docs.tuist.io/contributors/get-started',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/contribution/managing-projects',
    toPath: 'https://docs.tuist.io/contributors/championing-projects',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/contribution/manifesto',
    toPath: 'https://docs.tuist.io/contributors/manifesto',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/contribution/performance',
    toPath: 'https://docs.tuist.io/contributors/performance-testing',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/contribution/reporting-bugs',
    toPath: 'https://docs.tuist.io/contributors/reporting-bugs',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/dependencies/local',
    toPath: 'https://docs.tuist.io/guides/dependencies',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/examples/app-clips',
    toPath: 'https://docs.tuist.io/examples/app-clips',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/examples/app-extensions',
    toPath: 'https://docs.tuist.io/examples/app-extensions',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/examples/command-line-tools',
    toPath: 'https://docs.tuist.io/examples/command-line-tools',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/usage/workspace-description',
    toPath: 'https://docs.tuist.io/manifests/workspace',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/usage/project',
    toPath: 'https://docs.tuist.io/manifests/project',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/usage/config',
    toPath: 'https://docs.tuist.io/manifests/config',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/usage/dynamic-configuration',
    toPath: 'https://docs.tuist.io/guides/environment',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/usage/adoption-guidelines',
    toPath: 'https://docs.tuist.io/guides/adopting-tuist',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/usage/faq',
    toPath: 'https://docs.tuist.io/tutorial/faq',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/plugins/creating-plugins',
    toPath: 'https://docs.tuist.io/plugins/creating-plugins',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/plugins/using-plugins',
    toPath: 'https://docs.tuist.io/plugins/using-plugins',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/usage/stats',
    toPath: 'https://docs.tuist.io/guides/stats',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/usage/get-started',
    toPath: 'https://docs.tuist.io/tutorial/get-started',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/usage/helpers',
    toPath: 'https://docs.tuist.io/guides/helpers',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/usage/managing-versions',
    toPath: 'https://docs.tuist.io/guides/version-management',
    isPermanent: true,
  })
  createRedirect({
    fromPath: '/usage/resources',
    toPath: 'https://docs.tuist.io/guides/resources',
    isPermanent: true,
  })

  // Auto-generated pages
  if (node.internal.type === `Mdx`) {
    const fileNode = getNode(node.parent)

    if (fileNode.dir.includes('markdown/posts/')) {
      const filename = createFilePath({ node, getNode, basePath: `posts` })

      const postName = filename
      const [, date, title] = postName
        .split('/')[1]
        .match(/^([\d]{4}-[\d]{2}-[\d]{2})-{1}(.+)$/)

      const slug = `/blog/${date.replace(/-/g, '/')}/${title}/`

      createNodeField({ node, name: `type`, value: 'blog-post' })
      createNodeField({ node, name: `slug`, value: slug })
      createNodeField({ node, name: `date`, value: date })
      createNodeField({ node, name: `path`, value: fileNode.relativePath })
    } else if (fileNode.dir.includes('markdown/apps-at-scale/')) {
      const filename = createFilePath({
        node,
        getNode,
        basePath: `apps-at-scale`,
      })

      const postName = filename
      const [, date, title] = postName
        .split('/')[1]
        .match(/^([\d]{4}-[\d]{2}-[\d]{2})-{1}(.+)$/)
      const slug = `/apps-at-scale/${date.replace(/-/g, '/')}/${title}/`

      createNodeField({ node, name: `type`, value: 'apps-at-scale' })
      createNodeField({ node, name: `slug`, value: slug })
      createNodeField({ node, name: `date`, value: date })
      createNodeField({ node, name: `path`, value: fileNode.relativePath })
    } else {
      const filename = createFilePath({ node, getNode })
      if (node.frontmatter.migrated_path) {
        // To redirect to the pages that have been moved to docusaurus
        createRedirect({
          fromPath: filename,
          toPath: `https://docs.tuist.io${node.frontmatter.migrated_path}`,
          isPermanent: true,
        })
      }
      createNodeField({ node, name: `slug`, value: filename })
    }
  }
}

exports.createPages = ({ graphql, actions }) => {
  const { createPage } = actions
  const createBlogPages = graphql(
    `
      {
        posts: allMdx(
          filter: { fields: { type: { eq: "blog-post" } } }
          sort: { order: DESC, fields: [fields___date] }
        ) {
          edges {
            node {
              fields {
                slug
              }
            }
          }
        }
        appsAtScale: allMdx(
          filter: { fields: { type: { eq: "apps-at-scale" } } }
          sort: { order: DESC, fields: [fields___date] }
        ) {
          edges {
            node {
              fields {
                slug
              }
            }
          }
        }
      }
    `
  ).then((result) => {
    // POSTS
    const posts = result.data.posts.edges
    const postsPerPage = 10
    const numPostPages = Math.ceil(posts.length / postsPerPage)

    Array.from({ length: numPostPages }).forEach((_, i) => {
      createPage({
        path: i === 0 ? `/blog` : `/blog/${i + 1}`,
        component: path.resolve('./src/templates/blog-list.jsx'),
        context: {
          limit: postsPerPage,
          skip: i * postsPerPage,
          numPostPages,
          currentPage: i + 1,
        },
      })
    })

    result.data.posts.edges.forEach(({ node }, index) => {
      createPage({
        path: node.fields.slug,
        component: path.resolve(`./src/templates/blog-post.jsx`),
        context: {
          slug: node.fields.slug,
        },
      })
    })

    // APPS AT SCALE
    const appsAtScale = result.data.appsAtScale.edges
    const appsAtScalePerPage = 10
    const appsAtScalePages = Math.ceil(posts.length / postsPerPage)
    Array.from({ length: appsAtScalePerPage }).forEach((_, i) => {
      createPage({
        path: i === 0 ? `/apps-at-scale` : `/apps-at-scale/${i + 1}`,
        component: path.resolve('./src/templates/apps-at-scale-list.jsx'),
        context: {
          limit: appsAtScalePerPage,
          skip: i * appsAtScalePerPage,
          appsAtScalePages,
          currentPage: i + 1,
        },
      })
    })

    // Create app at scale posts
    result.data.appsAtScale.edges.forEach(({ node }, index) => {
      createPage({
        path: node.fields.slug,
        component: path.resolve(`./src/templates/apps-at-scale.jsx`),
        context: {
          slug: node.fields.slug,
        },
      })
    })
  })
  return Promise.all([createBlogPages])
}
