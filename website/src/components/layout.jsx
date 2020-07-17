/** @jsx jsx */

import { jsx } from 'theme-ui'
import React from 'react'
import { Styled } from 'theme-ui'
import GlobalStyle from './global-style'
import Header from './header'
import Footer from './footer'
import CookieBanner from './cookie-banner'

const Layout = ({ children, menuOpen, setMenuOpen, menuRef }) => {
  return (
    <>
      <GlobalStyle />
      <Header menuOpen={menuOpen} setMenuOpen={setMenuOpen} menuRef={menuRef} />
      <main sx={{ mb: [3, 6] }}>{children}</main>
      <Footer />
      <CookieBanner />
    </>
  )
}

export default Layout
