/** @jsx jsx */
import { jsx, Styled, useThemeUI } from 'theme-ui'

import Layout from '../components/layout'
import { Link } from 'gatsby'
import { graphql } from 'gatsby'
import Main from '../components/main'
import { findWhere } from 'underscore'
import { BreadcrumbJsonLd, BlogJsonLd } from 'gatsby-plugin-next-seo'
import urljoin from 'url-join'
import moment from 'moment'
import SEO from '../components/SEO'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faCalendarAlt,
} from '@fortawesome/free-regular-svg-icons'

const Post = ({ post, index }) => {
  const { theme } = useThemeUI()

  return (
    <article sx={{ mt: index == 0 ? 0 : 5 }} key={index}>
      <header>
        <Link
          to={post.fields.slug}
          alt={`Open the blog post titled ${post.frontmatter.title}`}
          sx={{
            color: 'primary',
            textDecoration: 'none',
            '&:hover': { color: 'secondary' },
          }}
        >
          <Styled.h2
            sx={{
              mb: 0,
            }}
          >
            {post.frontmatter.title}
          </Styled.h2>
        </Link>
        <div
          sx={{
            my: 3,
            color: 'gray',
            fontSize: 2,
            display: 'flex',
            flexDirection: ['column', 'row'],
            alignItems: 'flex-start',
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
          sx={{ variant: 'text.gatsby-link' }}
          to={prevPage}
        >
          Previous page
        </Link>
      )}
      {!isLast && (
        <Link
          alt={`Open the page ${currentPage + 1} of blog posts`}
          to={nextPage}
          sx={{ variant: 'text.gatsby-link' }}
        >
          Next page
        </Link>
      )}
    </div>
  )
}

const AppsAtScaleList = ({
  pageContext,
  data: {
    site: {
      siteMetadata: { siteUrl },
    },
    allMdx: { edges },
  },
}) => {
  const breadcrumb = [
    {
      position: 1,
      name: 'Apps at scale',
      item: urljoin(siteUrl, '/apps-at-scale'),
    },
  ]
  const description =
    'Learn how different companies in the industries are doing app development at scale through a series of interviews to industry leaders.'

  return (
    <Layout>
      <BreadcrumbJsonLd itemListElements={breadcrumb} />
      <SEO title="Apps at scale" description={description} />
      <BlogJsonLd
        url={urljoin(siteUrl, '/apps-at-scale')}
        headline="Apps at scale"
        posts={edges.map((edge) => {
          return {
            headline: edge.node.frontmatter.title,
            datePublished: moment(edge.node.fields.date).format(),
          }
        })}
        authorName="Tuist"
        description={description}
      />
      <Main>
        <Styled.h1>Apps at scale</Styled.h1>
        <Styled.p>
          Apps at scale is a series of interviews to companies and projects that
          are doing app development at scale. Discussions about how to overcome
          the challenges that come with scaling up projects and teams are often
          scattered and privately held. Therefore, our aim with these interviews
          is to have a public and central place for projects to share their
          experiences. If you would like to share your experience too, let us
          know on{' '}
          <Styled.a
            href="https://community.tuist.io/t/interview-blog-posts/59/6"
            target="__blank"
          >
            this discussion.
          </Styled.a>
        </Styled.p>
        {edges.map(({ node }, index) => {
          return <Post post={node} key={index} />
        })}
        <PostsFooter {...pageContext} />
      </Main>
    </Layout>
  )
}

export default AppsAtScaleList

export const appsAtScaleList = graphql`
  query appsAtScaleQuery($skip: Int!, $limit: Int!) {
    site {
      siteMetadata {
        title
        siteUrl
      }
    }
    allMdx(
      filter: { fields: { type: { eq: "apps-at-scale" } } }
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
          }
        }
      }
    }
  }
`
