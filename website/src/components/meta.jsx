import React from 'react'
import Helmet from 'react-helmet'
import { useStaticQuery, graphql, withPrefix } from 'gatsby'
import urljoin from 'url-join'

function Meta({ description, lang, meta, keywords, title, author, slug }) {
  const { site } = useStaticQuery(
    graphql`
      query {
        site {
          siteMetadata {
            siteUrl
            title
            description
          }
        }
      }
    `
  )

  const metaDescription = description || site.siteMetadata.description
  const metaTitle = title || site.siteMetadata.title
  const titleTemplate = title ? `%s | ${site.siteMetadata.title}` : `%s`
  return (
    <Helmet
      htmlAttributes={{
        lang,
      }}
      title={metaTitle}
      titleTemplate={titleTemplate}
    >
      <meta property="og:title" content={title} />
      <meta property="og:description" content={metaDescription} />
      <meta property="og:type" content="website" />
      <meta
        property="og:image"
        content={urljoin(
          site.siteMetadata.siteUrl,
          withPrefix('squared-logo.png')
        )}
      />

      <meta name="twitter:card" content="summary" />
      <meta name="twitter:creator" content={site.siteMetadata.author} />
      <meta name="twitter:title" content={title} />
      <meta name="twitter:description" content={metaDescription} />

      <meta name="description" content={metaDescription} />
      <meta name="twitter:card" content="summary_large_image" />
      <meta name="keywords" content={keywords.join(`, `)} />

      {slug && (
        <meta
          name="twitter:image"
          content={`${site.siteMetadata.siteUrl}${slug}twitter-card.jpg`}
        />
      )}
    </Helmet>
  )
}

Meta.defaultProps = {
  lang: `en`,
  meta: [],
  keywords: [
    `tuist`,
    `engineering`,
    `xcode`,
    `swift`,
    `project generation`,
    'ios',
    'uikit',
    'foundation',
    'tvos',
    'ios',
    'watchos',
    'objective-c',
    'swift package manager',
    'swift packages',
  ],
}

export default Meta
