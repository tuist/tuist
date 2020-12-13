/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import { useStaticQuery, graphql } from 'gatsby'
import OldLayout from '../components/old-layout'
import Main from '../components/main'
import { MDXRenderer } from 'gatsby-plugin-mdx'
import { FAQJsonLd, GatsbySeo } from 'gatsby-plugin-next-seo'
import SEO from '../components/SEO'
import { sortBy } from 'underscore'
import moment from 'moment'

const TableRow = ({ resource }) => {
  return (
    <tr>
      <td
        className="px-6 py-4 border-b break-word"
        sx={{ borderColor: 'muted' }}
      >
        <div className="flex items-center">
          <div className="flex-shrink-0 h-10 w-10">
            <img
              className="h-10 w-10 rounded-full"
              src={resource.icon_url}
              alt=""
            />
          </div>
          <div className="ml-4">
            <div
              className="text-sm leading-5 font-medium"
              sx={{ color: 'text' }}
            >
              {resource.name}
            </div>
          </div>
        </div>
      </td>
      <td
        className="px-6 py-4 whitespace-no-wrap border-b"
        sx={{ borderColor: 'muted' }}
      >
        <div className="text-sm leading-5" sx={{ color: 'text' }}>
          {resource.author}
        </div>
        <div className="text-sm leading-5" sx={{ color: 'gray' }}>
          {resource.author_subtitle}
        </div>
      </td>
      <td
        className="px-6 py-4 whitespace-no-wrap border-b"
        sx={{ borderColor: 'muted' }}
      >
        <span className="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-green-100 text-green-800 uppercase">
          {resource.type}
        </span>
      </td>
      <td
        className="px-6 py-4 whitespace-no-wrap border-b text-sm leading-5"
        sx={{ color: 'gray', borderColor: 'muted' }}
      >
        {resource.date.fromNow()}
      </td>
      <td
        className="px-6 py-4 whitespace-no-wrap text-right border-b text-sm leading-5 font-medium"
        sx={{ borderColor: 'muted' }}
      >
        <Styled.a href={resource.url} target="__blank">
          Link
        </Styled.a>
      </td>
    </tr>
  )
}

const Table = ({ resources }) => {
  resources = sortBy(
    resources.map((resource) => {
      return { ...resource, date: moment(resource.date) }
    }),
    (resource) => {
      return -resource.date.unix()
    }
  )
  return (
    <div sx={{ mt: 5 }}>
      <div className="flex flex-col">
        <div className="-my-2 py-2 overflow-x-auto sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8">
          <div
            className="align-middle inline-block min-w-full shadow overflow-hidden sm:rounded-lg border-b"
            sx={{ borderColor: 'muted' }}
          >
            <table className="min-w-full table-fixed">
              <thead>
                <tr>
                  <th
                    sx={{ color: 'gray', borderColor: 'muted' }}
                    className="px-6 py-3 border-b bg-gray-50 text-left text-xs leading-4 font-medium uppercase tracking-wider"
                  >
                    Name
                  </th>
                  <th
                    sx={{ color: 'gray', borderColor: 'muted' }}
                    className="px-6 py-3 border-b bg-gray-50 text-left text-xs leading-4 font-medium uppercase tracking-wider"
                  >
                    From
                  </th>
                  <th
                    sx={{ color: 'gray', borderColor: 'muted' }}
                    className="px-6 py-3 border-b bg-gray-50 text-left text-xs leading-4 font-medium uppercase tracking-wider"
                  >
                    Type
                  </th>
                  <th
                    sx={{ color: 'gray', borderColor: 'muted' }}
                    className="px-6 py-3 border-b bg-gray-50 text-left text-xs leading-4 font-medium uppercase tracking-wider"
                  >
                    When
                  </th>
                  <th
                    sx={{ color: 'gray', borderColor: 'muted' }}
                    className="px-6 py-3 border-b bg-gray-50"
                  />
                </tr>
              </thead>
              <tbody className="">
                {resources.map((resource, index) => {
                  return <TableRow key={index} resource={resource} />
                })}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  )
}
export default () => {
  const {
    allResourcesYaml: { nodes: resources },
    site: {
      siteMetadata: { editUrl },
    },
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
          editUrl
        }
      }
      allResourcesYaml {
        nodes {
          name
          url
          author
          author_url
          author_subtitle
          type
          date
          icon_url
        }
      }
    }
  `)
  return (
    <OldLayout>
      <SEO title="Resources" />
      <GatsbySeo
        title="Resources"
        description={`In this page you'll find resources about Tuist created by the community: videos, posts, tutorials, and projects."`}
      />
      <Main>
        <Styled.h1>Resources</Styled.h1>
        <Styled.p>
          This page contains a collection of resources created by the incredible
          community of Tuist users.
        </Styled.p>
        <Styled.p>
          If you have published something that you think is worth sharing with
          the rest of the community, feel free to{' '}
          <Styled.a href={`${editUrl}/data/resources.yaml`} target="__blank">
            edit this file
          </Styled.a>{' '}
          , and add your resource at the bottom. Right after merging your
          change, the website will be deployed automatically and your resource
          will show up in the table below.
        </Styled.p>
        <Table resources={resources} />
      </Main>
    </OldLayout>
  )
}
