/** @jsx jsx */
import { jsx, Styled, useThemeUI } from 'theme-ui'
import { MDXRenderer } from 'gatsby-plugin-mdx'

import Layout from '../components/layout'
import { graphql } from 'gatsby'
import moment from 'moment'
import Main from '../components/main'
import EditPage from '../components/edit-page'
import Share from '../components/share'
import urljoin from 'url-join'
import SEO from '../components/SEO'
import { NewsArticleJsonLd, BreadcrumbJsonLd } from 'gatsby-plugin-next-seo'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faClock,
  faCalendarAlt,
  faUser,
} from '@fortawesome/free-regular-svg-icons'

const Subtitle = ({ post }) => {
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
      </span>

      <span sx={{ ml: [0, 4] }}>
        <FontAwesomeIcon
          sx={{ path: { fill: theme.colors.gray }, height: 15, width: 15 }}
          icon={faClock}
          size="sm"
        />{' '}
        {post.timeToRead} min read
      </span>
    </div>
  )
}

const Page = ({
  data: {
    site: {
      siteMetadata: { siteUrl },
    },
    mdx,
  },
}) => {
  const post = mdx
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
            tags: post.frontmatter.categories,
          },
        }}
      />
      <Main>
        <Styled.h1 sx={{ textAlign: 'center', pb: 0, mb: 0 }}>
          {post.frontmatter.title}
        </Styled.h1>
        <Subtitle post={post} />
        <div sx={{ pb: 4 }}>
          <MDXRenderer>{post.body}</MDXRenderer>
        </div>
        <EditPage path={post.fields.path} />
        <Share
          path={post.fields.slug}
          tags={post.frontmatter.categories}
          title={post.frontmatter.title}
        />
      </Main>
    </Layout>
  )
}

export default Page

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
      timeToRead
      frontmatter {
        title
        categories
        excerpt
      }
    }
  }
`
