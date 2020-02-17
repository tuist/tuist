/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import { MDXRenderer } from 'gatsby-plugin-mdx'
import { graphql, Link, withPrefix } from 'gatsby'
import Layout from '../components/layout'
import Footer from '../components/footer'
import { ArticleJsonLd, BreadcrumbJsonLd } from 'gatsby-plugin-next-seo'
import urljoin from 'url-join'
import moment from 'moment'
import SEO from '../components/SEO'

const DocumentationPage = ({
  data: {
    mdx,
    allFile: { nodes: files },
    site: {
      siteMetadata: { documentationCategories, siteUrl },
    },
  },
}) => {
  const page = mdx
  return (
    <Layout>
      <SEO
        title={page.frontmatter.name}
        description={page.frontmatter.excerpt}
      />
      <ArticleJsonLd
        url={urljoin(siteUrl, page.fields.slug)}
        headline={page.frontmatter.name}
        description={page.frontmatter.excerpt}
        images={[urljoin(siteUrl, withPrefix('squared-logo.png'))]}
        authorName="Tuist"
        publisherName="Tuist"
        publisherLogo={urljoin(siteUrl, withPrefix('squared-logo.png'))}
        datePublished={moment().format()}
        dateModified={moment().format()}
      />
      <BreadcrumbJsonLd
        itemListElements={[
          {
            position: 1,
            name: 'Documentation',
            item: urljoin(siteUrl, 'docs'),
          },
          {
            position: 2,
            name: page.frontmatter.name,
            item: urljoin(siteUrl, page.fields.slug),
          },
        ]}
      />
      <div
        sx={{ display: 'flex', flexDirection: ['column', 'row'], flex: '1' }}
      >
        <aside
          sx={{
            flex: [1, 'none'],
            px: 3,
            bg: 'gray6',
            mt: 2,
            width: ['none', 200],
            display: 'flex',
            flexDirection: 'column',
            alignItems: ['center', 'flex-start'],
          }}
        >
          {documentationCategories.map((category, categoryIndex) => {
            return (
              <div key={categoryIndex}>
                <Styled.h3 sx={{ textAlign: ['center', 'left'], mt: 4 }}>
                  {category.name}
                </Styled.h3>
                {files
                  .filter(file =>
                    file.relativeDirectory.endsWith(category.folderName)
                  )
                  .map((file, fileIndex) => {
                    const current =
                      file.childMdx.fields.slug === mdx.fields.slug
                    return (
                      <Link
                        key={`${categoryIndex}-${fileIndex}`}
                        to={file.childMdx.fields.slug}
                        sx={{ color: current ? 'primary' : 'gray2' }}
                      >
                        <Styled.h4
                          sx={{ textAlign: ['center', 'left'], mt: 3 }}
                        >
                          {file.childMdx.frontmatter.name}
                        </Styled.h4>
                      </Link>
                    )
                  })}
              </div>
            )
          })}
        </aside>
        <div
          sx={{
            px: [3, 6],
            pt: 4,
            pb: 6,
            minWidth: 0,
            boxShadow: theme => `-1px -1px 12px -4px ${theme.colors.gray5}`,
          }}
        >
          <MDXRenderer>{page.body}</MDXRenderer>
        </div>
      </div>
      <Footer />
    </Layout>
  )
}

export const query = graphql`
  query($slug: String!) {
    allFile(
      filter: { absolutePath: { regex: "/docs/.*/" }, extension: { eq: "mdx" } }
      sort: { fields: childMdx___frontmatter___order, order: ASC }
    ) {
      nodes {
        relativeDirectory
        childMdx {
          excerpt
          fields {
            slug
          }
          frontmatter {
            name
          }
        }
      }
    }
    site {
      siteMetadata {
        title
        siteUrl
        documentationCategories {
          folderName
          name
        }
      }
    }
    mdx(fields: { slug: { eq: $slug } }) {
      frontmatter {
        name
        excerpt
      }
      fields {
        slug
      }
      body
    }
  }
`

export default DocumentationPage
