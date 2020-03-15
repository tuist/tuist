/** @jsx jsx */

import { jsx } from 'theme-ui'
import React from 'react'
import { Styled } from 'theme-ui'
import GlobalStyle from './global-style'
import Header from '../components/header'
import Footer from '../components/footer'

const Layout = ({ children, menuOpen, setMenuOpen }) => {
  return (
    <>
      <GlobalStyle />
      <Header menuOpen={menuOpen} setMenuOpen={setMenuOpen} />
      <main sx={{ mb: [3, 6] }}>{children}</main>
      <Footer />
    </>
  )
}

export default Layout
