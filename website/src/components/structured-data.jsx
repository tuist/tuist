/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import { withPrefix, useStaticQuery, graphql } from 'gatsby'
import Helmet from 'react-helmet'
import urljoin from 'url-join'

const ArticleStructuredData = ({
  url,
  title,
  excerpt,
  author,
  siteUrl,
  date,
}) => {
  const structuredData = `
  {
  "@context": "https://schema.org",
  "@type": "NewsArticle",
  "mainEntityOfPage": {
    "@type": "WebPage",
    "@id": "https://google.com/article"
  },
  "headline": "${title}",
  "datePublished": "${date.toISOString()}",
  "author": {
    "@type": "Person",
    "name": "${author}"
  },
   "publisher": {
    "@type": "Organization",
    "name": "Tuist",
    "logo": {
      "@type": "ImageObject",
      "url": "${urljoin(siteUrl, withPrefix('tuist.png'))}"
    }
  },
  "description": "${excerpt}"
}
  `
  return (
    <Helmet>
      <script type="application/ld+json">{structuredData}</script>
    </Helmet>
  )
}

const LogoStructuredData = () => {
  const {
    site: {
      siteMetadata: { siteUrl },
    },
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
          siteUrl
        }
      }
    }
  `)
  const structuredData = `
  {
    "@context": "https://schema.org",
    "@type": "Organization",
    "url": "${siteUrl}",
    "logo": "${urljoin(siteUrl, withPrefix('tuist.png'))}"
  }
  `
  return (
    <Helmet>
      <script type="application/ld+json">{structuredData}</script>
    </Helmet>
  )
}

const FAQStructuredData = ({ items }) => {
  const itemListElement = items.map((item, index) => {
    return {
      '@type': 'Question',
      name: item[0],
      acceptedAnswer: {
        '@type': 'Answer',
        text: item[1],
      },
    }
  })
  const structuredData = `
  {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": ${JSON.stringify(itemListElement)}
  }
  `
  return (
    <Helmet>
      <script type="application/ld+json">{structuredData}</script>
    </Helmet>
  )
}

const BreadcrumbStructuredData = ({ items }) => {
  const itemListElement = items.map((item, index) => {
    return {
      '@type': 'ListItem',
      position: index,
      name: item[0],
      item: item[1],
    }
  })
  const structuredData = `
  {
"@context": "https://schema.org",
"@type": "BreadcrumbList",
  "itemListElement": ${JSON.stringify(itemListElement)}
}
  `
  return (
    <Helmet>
      <script type="application/ld+json">{structuredData}</script>
    </Helmet>
  )
}

export {
  ArticleStructuredData,
  BreadcrumbStructuredData,
  LogoStructuredData,
  FAQStructuredData,
}
