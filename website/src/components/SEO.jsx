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
      siteMetadata: { siteUrl, description: defaultDescription },
    },
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
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
        title={title != null ? title : 'Tuist'}
        titleTemplate={title != null ? `%s | Tuist` : '%s'}
        {...other}
      />
      <LogoJsonLd logo={logo} url={siteUrl} />
    </>
  )
}
