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
} from '@fortawesome/free-regular-svg-icons'

const Subtitle = ({ mdx }) => {
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
        {mdx.fields.date}
      </span>
    </div>
  )
}

const CommunityCard = ({ mdx }) => {
  return (
    <div className="my-10">
      <div className="bg-white shadow sm:rounded-lg">
        <div className="px-4 py-5 sm:p-6">
          <h3 className="text-lg leading-6 font-medium text-gray-900">
            Continue the discussion
          </h3>
          <div className="mt-2 sm:flex sm:items-start sm:justify-between">
            <div className="max-w-xl text-sm leading-5 text-gray-500">
              <p>
                If there you have questions and ideas that arouse while reading
                the interview, we have a community topic where you can ask those
                directly to {mdx.frontmatter.interviewee_name}.
              </p>
            </div>
            <div className="mt-5 sm:mt-0 sm:ml-6 sm:flex-shrink-0 sm:flex sm:items-center">
              <span className="inline-flex rounded-md shadow-sm">
                <a
                  href={mdx.frontmatter.community_topic}
                  target="__blank"
                  className="inline-flex items-center px-4 py-2 border border-transparent text-sm leading-5 font-medium rounded-md text-white bg-blue-600 hover:bg-blue-500 focus:outline-none focus:border-indigo-700 focus:shadow-outline-indigo active:bg-indigo-700 transition ease-in-out duration-150"
                >
                  Ask {mdx.frontmatter.interviewee_name}
                </a>
              </span>
            </div>
          </div>
        </div>
      </div>
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
  const breadcrumb = [
    {
      position: 1,
      name: 'Apps at scale',
      item: urljoin(siteUrl, '/apps-at-scale'),
    },
    {
      position: 2,
      name: mdx.frontmatter.title,
      item: urljoin(siteUrl, mdx.fields.slug),
    },
  ]
  return (
    <Layout>
      <BreadcrumbJsonLd itemListElements={breadcrumb} />
      <NewsArticleJsonLd
        url={urljoin(siteUrl, mdx.fields.slug)}
        title={mdx.frontmatter.title}
        keywords={mdx.frontmatter.categories}
        datePublished={moment(mdx.fields.date).format()}
        description={mdx.frontmatter.excerpt}
        authorName={mdx.frontmatter.interviewee_name}
        publisherName={mdx.frontmatter.interviewee_name}
        publisherLogo={mdx.frontmatter.interviewee_name}
        images={[mdx.frontmatter.interviewee_avatar]}
      />

      <SEO
        title={mdx.frontmatter.title}
        description={mdx.frontmatter.excerpt}
        openGraph={{
          title: mdx.frontmatter.title,
          description: mdx.frontmatter.excerpt,
          url: urljoin(siteUrl, mdx.fields.slug),
          type: 'article',
          article: {
            publishedTime: moment(mdx.fields.date).format(),
            tags: mdx.frontmatter.categories,
            authors: [
              `https://www.twitter.com/${mdx.frontmatter.interviewee_twitter_handle}`,
            ],
          },
        }}
      />

      <div className="h-64 relative">
        <img
          className="h-64 w-full object-cover"
          src={mdx.frontmatter.header_image}
        />

        <div className="flex flex-row justify-center items-center bottom-0 inset-x-0 inset-y-0 absolute">
          <div className="w-24 h-24 md:w-32 md:h-32">
            <a
              className="group w-full h-full rounded-full overflow-hidden shadow-inner text-center bg-purple table cursor-pointer border-4"
              target="__blank"
              href={`https://twitter.com/${mdx.frontmatter.interviewee_twitter_handle}`}
            >
              <img
                src={mdx.frontmatter.interviewee_avatar}
                alt={`${mdx.frontmatter.interviewee_name}'s avatar`}
                className="object-cover object-center w-full h-full visible group-hover:hidden"
              />
            </a>
          </div>
        </div>
      </div>

      <Main>
        <Styled.h1 sx={{ textAlign: 'center', pb: 0, mb: 0 }}>
          {mdx.frontmatter.title}
        </Styled.h1>
        <Subtitle mdx={mdx} />
        <div sx={{ pb: 4 }}>
          <MDXRenderer>{mdx.body}</MDXRenderer>
        </div>
        <CommunityCard mdx={mdx} />
        <Share
          path={mdx.fields.slug}
          tags={mdx.frontmatter.categories}
          title={mdx.frontmatter.title}
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
      frontmatter {
        interviewee_name
        title
        categories
        excerpt
        header_image
        interviewee_avatar
        interviewee_twitter_handle
        community_topic
      }
    }
  }
`
