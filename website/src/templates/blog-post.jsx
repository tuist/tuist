/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import { MDXRenderer } from 'gatsby-plugin-mdx'

import Layout from '../components/layout'
import Footer from '../components/footer'
import { graphql } from 'gatsby'
import moment from 'moment'
import Main from '../components/main'
import EditPage from '../components/edit-page'
import Share from '../components/share'
import urljoin from 'url-join'
import SEO from '../components/SEO'
import { NewsArticleJsonLd, BreadcrumbJsonLd } from 'gatsby-plugin-next-seo'

const Avatar = ({ author: { avatar, twitter } }) => {
  return (
    <a href={`https://twitter.com/${twitter}`} target="__blank">
      <img
        sx={{
          my: [20, 0],
          width: [90, 110],
          height: [90, 110],
          borderRadius: [45, 55],
        }}
        alt="Author's avatar"
        src={avatar}
      />
    </a>
  )
}

const IndexPage = ({
  data: {
    site: {
      siteMetadata: { siteUrl },
    },
    mdx,
    allAuthorsYaml: { edges },
  },
}) => {
  const post = mdx
  const authors = edges.map(edge => edge.node)
  const author = authors.find(
    author => author.handle === post.frontmatter.author
  )
  const subtitle = `Published by ${author.name} on ${moment(
    post.fields.date
  ).format('MMMM Do YYYY')}`

  const breadcrumb = [
    { position: 1, name: 'Blog', item: urljoin(siteUrl, '/blog') },
    {
      position: 2,
      name: post.frontmatter.title,
      item: urljoin(siteUrl, post.fields.slug),
    },
  ]
  return (
    <Layout>
      <BreadcrumbJsonLd itemListElements={breadcrumb} />
      <NewsArticleJsonLd
        url={urljoin(siteUrl, post.fields.slug)}
        title={post.frontmatter.title}
        keywords={post.frontmatter.categories}
        datePublished={moment(post.fields.date).format()}
        author={author.name}
        description={post.frontmatter.excerpt}
      />

      <SEO
        title={post.frontmatter.title}
        description={post.frontmatter.excerpt}
        openGraph={{
          title: post.frontmatter.title,
          description: post.frontmatter.excerpt,
          url: urljoin(siteUrl, post.fields.slug),
          type: 'article',
          article: {
            publishedTime: moment(post.fields.date).format(),
            authors: [`https://www.twitter.com/${author.twitter}`],
            tags: post.frontmatter.categories,
          },
        }}
      />
      <Main>
        <div
          sx={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
          }}
        >
          <Avatar author={author} />
        </div>

        <Styled.h1 sx={{ textAlign: 'center', pb: 0, mb: 0 }}>
          {post.frontmatter.title}
        </Styled.h1>
        <Styled.p sx={{ textAlign: 'center', color: 'gray3', mb: 4 }}>
          {subtitle}
        </Styled.p>
        <div sx={{ pb: 4 }}>
          <MDXRenderer>{post.body}</MDXRenderer>
        </div>
        <p>
          <EditPage path={post.fields.path} />
        </p>
        <Share
          path={post.fields.slug}
          tags={post.frontmatter.categories}
          title={post.frontmatter.title}
        />
      </Main>
      <Footer />
    </Layout>
  )
}

export default IndexPage

export const query = graphql`
  query($slug: String!) {
    site {
      siteMetadata {
        title
        siteUrl
      }
    }
    mdx(fields: { slug: { eq: $slug } }) {
      body
      fields {
        slug
        date
        path
      }
      frontmatter {
        title
        categories
        excerpt
        author
      }
    }
    allAuthorsYaml {
      edges {
        node {
          name
          avatar
          twitter
          handle
        }
      }
    }
  }
`
