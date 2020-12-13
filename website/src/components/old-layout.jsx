/** @jsx jsx */

import { jsx } from 'theme-ui'
import React from 'react'
import { Styled } from 'theme-ui'
import GlobalStyle from './global-style'
import Header from './header'
import OldFooter from './old-footer'
import CookieBanner from './cookie-banner'

const OldLayout = ({ children, menuOpen, setMenuOpen, menuRef }) => {
  return (
    <>
      <GlobalStyle />
      <Header menuOpen={menuOpen} setMenuOpen={setMenuOpen} menuRef={menuRef} />
      <main sx={{ mb: [3, 6] }}>{children}</main>
      <CookieBanner />
      <OldFooter />
    </>
  )
}

export default OldLayout
