import React from 'react'
import { Styled } from 'theme-ui'
import GlobalStyle from './global-style'
import Header from '../components/header'
import { LogoStructuredData } from '../components/structured-data'

const Layout = ({ children }) => {
  return (
    <>
      <GlobalStyle />
      <LogoStructuredData />
      <Styled.root>
        <Header />
        <main>{children}</main>
      </Styled.root>
    </>
  )
}

export default Layout
