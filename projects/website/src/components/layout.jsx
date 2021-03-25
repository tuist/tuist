/** @jsx jsx */

import { jsx } from 'theme-ui'
import React from 'react'
import GlobalStyle from './global-style'
import Header from './header'
import Footer from './footer'
import { Helmet } from 'react-helmet'

const Layout = ({ children, menuOpen, setMenuOpen, menuRef }) => {
  return (
    <>
      <Helmet>
        <script
          async
          defer
          data-domain="tuist.io"
          src="https://plausible.io/js/plausible.js"
        ></script>
      </Helmet>
      <GlobalStyle />
      <Header menuOpen={menuOpen} setMenuOpen={setMenuOpen} menuRef={menuRef} />
      <main sx={{ mb: [3, 6] }}>{children}</main>
      <Footer />
    </>
  )
}

export default Layout
