/** @jsx jsx */

import { jsx, Styled } from 'theme-ui'
import React from 'react'
import { Global } from '@emotion/react'
import 'focus-visible'
import { darken } from '@theme-ui/color'

const GlobalStyle = () => {
  return (
    <Global
      styles={(theme) => ({
        '*': {
          padding: '0px',
          margin: '0px',
        },
        // code: {
        //   paddingLeft: 3,
        //   paddingRight: 3,
        //   color: theme.colors.primary,
        //   background: theme.colors.primaryAlpha,
        //   fontSize: theme.fontSizes[1],
        // },
        // a: {
        //   textDecoration: 'none',
        //   backgroundImage: 'none',
        //   textShadow: 'none',
        // },
        // "pre[class*='language-']": {
        //   overflow: 'auto',
        //   fontSize: theme.fontSizes[1],
        // },
        "div[class*='token-line']": {
          overflowWrap: 'normal',
        },
        '.js-focus-visible :focus:not(.focus-visible)': {
          outline: 'none',
        },
        '.js-focus-visible :focus:not([data-focus-visible-added])': {
          outline: 'none',
        },
      })}
    />
  )
}
export default GlobalStyle
