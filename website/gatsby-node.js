const { createFilePath } = require(`gatsby-source-filesystem`)
const path = require(`path`)

exports.onCreateNode = ({ node, getNode, actions }) => {
  const { createNodeField, createRedirect } = actions

  // Redirect
  createRedirect({
    fromPath: '/docs',
    toPath: '/docs/usage/getting-started/',
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

  const createDocumentationPages = graphql(
    `
      {
        allMdx(filter: { fileAbsolutePath: { regex: "/docs/.*/" } }) {
          nodes {
            fileAbsolutePath
            fields {
              slug
            }
          }
        }
      }
    `
  ).then((result) => {
    return result.data.allMdx.nodes.forEach((node, index) => {
      return createPage({
        path: node.fields.slug,
        component: path.resolve(`./src/templates/documentation.jsx`),
        context: {
          slug: node.fields.slug,
        },
      })
    })
  })
  return Promise.all([createBlogPages, createDocumentationPages])
}
