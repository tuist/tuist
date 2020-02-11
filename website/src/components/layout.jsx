import React from 'react'
import { Styled } from 'theme-ui'
import GlobalStyle from './global-style'
import Header from '../components/header'

const Layout = ({ children }) => {
  return (
    <>
      <GlobalStyle />
      <Styled.root>
        <Header />
        <main>{children}</main>
      </Styled.root>
    </>
  )
}

export default Layout
