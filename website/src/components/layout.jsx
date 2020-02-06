import React from 'react'
import { Styled } from 'theme-ui'
import GlobalStyle from './global-style'
import Header from '../components/header'
import { LogoJsonLd } from 'gatsby-plugin-next-seo'
import urljoin from 'url-join'
import logo from '../../static/tuist.png'

import { useStaticQuery, graphql } from 'gatsby'
import { GatsbySeo } from 'gatsby-plugin-next-seo'

const Layout = ({ children }) => {
  const {
    site: {
      siteMetadata: { siteUrl, description },
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
      <GlobalStyle />
      <GatsbySeo description={description} />
      <LogoJsonLd logo={logo} url={siteUrl} />

      <Styled.root>
        <Header />
        <main>{children}</main>
      </Styled.root>
    </>
  )
}

export default Layout
