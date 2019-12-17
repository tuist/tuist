const { createFilePath } = require(`gatsby-source-filesystem`)
const slugify = require('slug')
const path = require(`path`)

exports.onCreateNode = ({ node, getNode, actions }) => {
  const { createNodeField, createRedirect } = actions
  createRedirect({
    fromPath: '/docs',
    toPath: '/docs/usage/getting-started/',
    isPermanent: true,
  })

  if (node.internal.type === `Mdx`) {
    const fileNode = getNode(node.parent)

    if (fileNode.dir.includes('markdown/posts/')) {
      const filename = createFilePath({ node, getNode, basePath: `posts` })

      const postName = filename
      const [, date, title] = postName
        .split('/')[1]
        .match(/^([\d]{4}-[\d]{2}-[\d]{2})-{1}(.+)$/)

      const slug = `/blog/${slugify([date].join('-'), '/')}/${title}/`

      createNodeField({ node, name: `type`, value: 'blog-post' })
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
        allMdx(
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
      }
    `
  ).then(result => {
    const posts = result.data.allMdx.edges
    const postsPerPage = 10
    const numPages = Math.ceil(posts.length / postsPerPage)

    // Create blog lists
    Array.from({ length: numPages }).forEach((_, i) => {
      createPage({
        path: i === 0 ? `/blog` : `/blog/${i + 1}`,
        component: path.resolve('./src/templates/blog-list.jsx'),
        context: {
          limit: postsPerPage,
          skip: i * postsPerPage,
          numPages,
          currentPage: i + 1,
        },
      })
    })

    // Create blog posts
    result.data.allMdx.edges.forEach(({ node }, index) => {
      createPage({
        path: node.fields.slug,
        component: path.resolve(`./src/templates/blog-post.jsx`),
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
  ).then(result => {
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
