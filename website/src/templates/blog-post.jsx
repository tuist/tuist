/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import { MDXRenderer } from 'gatsby-plugin-mdx'

import Layout from '../components/layout'
import Meta from '../components/meta'
import Footer from '../components/footer'
import { graphql } from 'gatsby'
import moment from 'moment'
import Main from '../components/main'
import EditPage from '../components/edit-page'
import Share from '../components/share'
import {
  BreadcrumbStructuredData,
  ArticleStructuredData,
} from '../components/structured-data'
import urljoin from 'url-join'

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
    ['Blog', urljoin(siteUrl, '/blog')],
    [post.frontmatter.title, urljoin(siteUrl, post.fields.slug)],
  ]
  return (
    <Layout>
      <BreadcrumbStructuredData items={breadcrumb} />
      <ArticleStructuredData
        title={post.frontmatter.title}
        excerpt={post.frontmatter.excerpt}
        author={author.name}
        url={urljoin(siteUrl, post.fields.slug)}
        siteUrl={siteUrl}
        date={moment(post.fields.date)}
      />
      <Meta
        title={post.frontmatter.title}
        description={post.frontmatter.excerpt}
        keywords={post.frontmatter.categories}
        author={author.twitter}
        slug={post.fields.slug}
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
