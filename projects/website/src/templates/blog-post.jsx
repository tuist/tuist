/** @jsx jsx */
import { jsx, Styled, useThemeUI } from 'theme-ui'
import { MDXRenderer } from 'gatsby-plugin-mdx'

import Layout from '../components/layout'
import { graphql } from 'gatsby'
import moment from 'moment'
import Main from '../components/main'
import Share from '../components/share'
import urljoin from 'url-join'
import SEO from '../components/SEO'
import { NewsArticleJsonLd, BreadcrumbJsonLd } from 'gatsby-plugin-next-seo'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faCalendarAlt,
  faUser,
} from '@fortawesome/free-regular-svg-icons'

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

const Subtitle = ({ post, author }) => {
  const { theme } = useThemeUI()
  return (
    <div
      sx={{
        flex: 1,
        mb: 0,
        color: 'gray',
        fontSize: 2,
        my: 4,
        display: 'flex',
        alignItems: 'center',
        flexDirection: ['column', 'row'],
        justifyContent: 'center',
      }}
    >
      <span>
        <FontAwesomeIcon
          sx={{ path: { fill: theme.colors.gray }, height: 15, width: 15 }}
          icon={faCalendarAlt}
          size="sm"
        />{' '}
        {post.fields.date}
      </span>

      <span
        sx={{
          ml: [0, 4],
          display: 'flex',
          flexDirection: 'row',
          flexWrap: 'nowrap',
          alignItems: 'center',
        }}
      >
        <FontAwesomeIcon
          sx={{ path: { fill: theme.colors.gray }, height: 15, width: 15 }}
          icon={faUser}
          size="sm"
        />
        <Styled.a
          href={`https://twitter.com/${author.twitter}`}
          target="__blank"
          alt={`Open the Twitter profile of ${author.name}`}
          sx={{ ml: 2 }}
        >
          {author.name}
        </Styled.a>
        <img
          src={author.avatar}
          sx={{ width: 14, height: 14, borderRadius: 7, ml: 2 }}
        />
      </span>
    </div>
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
  const authors = edges.map((edge) => edge.node)
  const author = authors.find(
    (author) => author.handle === post.frontmatter.author
  )

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
        authorName={author.name}
        publisherName={author.name}
        publisherLogo={author.avatar}
        images={[author.avatar]}
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
        <Subtitle post={post} author={author} />
        <div sx={{ pb: 4 }}>
          <MDXRenderer>{post.body}</MDXRenderer>
        </div>
        <Share
          path={post.fields.slug}
          tags={post.frontmatter.categories}
          title={post.frontmatter.title}
        />
      </Main>
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
