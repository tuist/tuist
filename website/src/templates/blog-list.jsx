/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'

import Layout from '../components/layout'
import Footer from '../components/footer'
import { Link } from 'gatsby'
import { graphql } from 'gatsby'
import Main from '../components/main'
import { findWhere } from 'underscore'
import { BreadcrumbJsonLd, BlogJsonLd } from 'gatsby-plugin-next-seo'
import urljoin from 'url-join'
import moment from 'moment'
import SEO from '../components/SEO'

const Post = ({ post, index, authors }) => {
  const authorHandle = post.frontmatter.author
  const author = findWhere(authors, { handle: authorHandle })

  return (
    <article sx={{ mt: index == 0 ? 0 : 5 }} key={index}>
      <header>
        <Styled.h2
          sx={{
            mb: 0,
            color: 'gray1',
            '&:hover': { textDecoration: 'underline' },
            '&:focus': { textDecoration: 'underline' },
          }}
        >
          <Link
            to={post.fields.slug}
            alt={`Open the blog post titled ${post.frontmatter.title}`}
          >
            {post.frontmatter.title}
          </Link>
        </Styled.h2>
        <div
          sx={{
            mb: 0,
            color: 'gray3',
            fontSize: 2,
            display: 'flex',
            flexDirection: 'row',
            alignItems: 'center',
          }}
        >
          Published on {post.fields.date} by{' '}
          <a
            sx={{
              '&:hover': { textDecoration: 'underline' },
              '&:focus': { textDecoration: 'underline' },
              ml: 2,
            }}
            href={`https://twitter.com/${author.twitter}`}
            target="__blank"
            alt={`Open the Twitter profile of ${author.name}`}
          >
            {author.name}
          </a>
          <img
            src={author.avatar}
            sx={{ width: 14, height: 14, borderRadius: 7, ml: 2 }}
          />
        </div>
      </header>

      <p sx={{ my: 3 }}>{post.frontmatter.excerpt}</p>
    </article>
  )
}

const PostsFooter = ({ currentPage, numPages }) => {
  const isFirst = currentPage === 1
  const isLast = currentPage === numPages
  const prevPage =
    currentPage - 1 === 1 ? '/blog/' : `/blog/${(currentPage - 1).toString()}`
  const nextPage = `/blog/${(currentPage + 1).toString()}`

  return (
    <div
      sx={{
        mt: 5,
        display: 'flex',
        flex: 1,
        flexDirection: 'row',
        justifyContent: 'space-between',
      }}
    >
      {!isFirst && (
        <Link
          alt={`Open the page ${currentPage - 1} of blog posts`}
          to={prevPage}
          sx={{
            color: 'secondary',
            '&:hover': { textDecoration: 'underline' },
            '&:focus': { textDecoration: 'underline' },
          }}
        >
          Previous page
        </Link>
      )}
      {!isLast && (
        <Link
          alt={`Open the page ${currentPage + 1} of blog posts`}
          to={nextPage}
          sx={{
            color: 'secondary',
            '&:hover': { textDecoration: 'underline' },
            '&:focus': { textDecoration: 'underline' },
          }}
        >
          Next page
        </Link>
      )}
    </div>
  )
}

const BlogList = ({
  pageContext,
  data: {
    site: {
      siteMetadata: { siteUrl },
    },
    allMdx: { edges },
    allAuthorsYaml: { nodes: authors },
  },
}) => {
  const breadcrumb = [
    { position: 1, name: 'Blog', item: urljoin(siteUrl, '/blog') },
  ]
  const description =
    'Read about Tuist updates: new releases, engineering challenges, and road-map updates.'

  return (
    <Layout>
      <BreadcrumbJsonLd itemListElements={breadcrumb} />
      <SEO title="Blog" description={description} />
      <BlogJsonLd
        url={urljoin(siteUrl, '/blog')}
        headline="Tuist Blog"
        posts={edges.map(edge => {
          const authorHandle = edge.node.frontmatter.author
          const author = findWhere(authors, { handle: authorHandle })

          return {
            headline: edge.node.frontmatter.title,
            author: author.name,
            datePublished: moment(edge.node.fields.date).format(),
            image: author.avatar,
            publisherName: author.name,
            publisherLogo: author.avatar,
          }
        })}
        authorName="Tuist"
        description={description}
      />
      <Main>
        <Styled.h1>Blog</Styled.h1>
        {edges.map(({ node }, index) => {
          return <Post post={node} key={index} authors={authors} />
        })}
        <PostsFooter {...pageContext} />
      </Main>
      <Footer />
    </Layout>
  )
}

export default BlogList

export const blogListQuery = graphql`
  query blogListQuery($skip: Int!, $limit: Int!) {
    allAuthorsYaml {
      nodes {
        name
        avatar
        twitter
        handle
      }
    }
    site {
      siteMetadata {
        title
        siteUrl
      }
    }
    allMdx(
      filter: { fields: { type: { eq: "blog-post" } } }
      sort: { order: DESC, fields: [fields___date] }
      limit: $limit
      skip: $skip
    ) {
      edges {
        node {
          id
          fields {
            date
            slug
          }
          frontmatter {
            categories
            title
            excerpt
            author
          }
        }
      }
    }
  }
`
