/** @jsx jsx */
import { jsx } from 'theme-ui'
import { useState, useRef } from 'react'
import { MDXRenderer } from 'gatsby-plugin-mdx'
import { graphql, Link, withPrefix } from 'gatsby'
import Layout from '../components/layout'
import { ArticleJsonLd, BreadcrumbJsonLd } from 'gatsby-plugin-next-seo'
import urljoin from 'url-join'
import moment from 'moment'
import SEO from '../components/SEO'
import Links from '../../markdown/docs/links.mdx'
import { Sidenav } from '@theme-ui/sidenav'
import { Location } from '@reach/router'
import isAbsoluteURL from 'is-absolute-url'

const NavigationLink = ({ href, ...props }) => {
  const style = {
    display: 'inline-block',
    color: 'inherit',
    textDecoration: 'none',
    ':hover,:focus': {
      color: 'primary',
    },
    pl: '20px !important',
    '&.active': {
      color: 'primary',
    },
  }
  const isExternal = isAbsoluteURL(href || '')
  if (isExternal) {
    return <a {...props} href={href} sx={style} />
  }
  const to = props.to || href
  return <Link {...props} to={to} sx={style} activeClassName="active" />
}

const DocumentationPage = (
  {
    data: {
      mdx,
      site: {
        siteMetadata: { siteUrl },
      },
    },
  },
  ...props
) => {
  const ref = useRef(null)
  const page = mdx
  const [menuOpen, setMenuOpen] = useState(false)
  return (
    <Layout menuOpen={menuOpen} setMenuOpen={setMenuOpen} menuRef={ref}>
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
        sx={{
          display: 'flex',
          flexDirection: ['column', 'row'],
          flex: '1',
          overflow: 'auto',
        }}
      >
        <div
          ref={ref}
          onFocus={(e) => {
            // setMenuOpen(true)
          }}
          onBlur={(e) => {
            setMenuOpen(false)
          }}
          onClick={(e) => {
            setMenuOpen(false)
          }}
        >
          <Location
            children={({ location }) => {
              return (
                <Links
                  open={menuOpen}
                  components={{ wrapper: Sidenav, a: NavigationLink }}
                  pathname={location.pathname}
                  className={menuOpen}
                  sx={{
                    li: {
                      listStyleType: 'none',
                    },
                    display: [null, 'block'],
                    width: [250, 400],
                    mt: [64, 0],
                    flex: 'none',
                    pl: [2, 6],
                    pr: [2, 0],
                    pt: [0, 5],
                  }}
                />
              )
            }}
          />
        </div>

        <div
          sx={{
            pl: [4, 4],
            pr: [4, 6],
            pt: 4,
            pb: 6,
            minWidth: 0,
          }}
        >
          <MDXRenderer>{page.body}</MDXRenderer>
        </div>
      </div>
    </Layout>
  )
}

export const query = graphql`
  query($slug: String!) {
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
