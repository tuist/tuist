/** @jsx jsx */
import { jsx } from 'theme-ui'
import React from 'react'
import { GatsbySeo } from 'gatsby-plugin-next-seo'
import { LogoJsonLd } from 'gatsby-plugin-next-seo'
import logo from '../../static/tuist.png'
import { useStaticQuery, graphql } from 'gatsby'

export default ({ description, title, ...other }) => {
  const {
    site: {
      siteMetadata: {
        siteUrl,
        description: defaultDescription,
        title: defaultTitle,
      },
    },
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
          title
          siteUrl
          description
        }
      }
    }
  `)
  return (
    <>
      <GatsbySeo
        description={description != null ? description : defaultDescription}
        title={title != null ? title : defaultTitle}
        titleTemplate={title != null ? `%s | Tuist` : '%s'}
        openGraph={{
          title: title != null ? `${title} | Tuist` : defaultTitle,
          description: description != null ? description : defaultDescription,
          site_name: defaultTitle,
        }}
        twitter={{
          handle: '@tuistio',
          site: '@tuistio',
          cardType: 'summary',
        }}
        {...other}
      />
      <LogoJsonLd logo={logo} url={siteUrl} />
    </>
  )
}
