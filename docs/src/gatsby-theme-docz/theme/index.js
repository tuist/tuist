import baseTheme from 'gatsby-theme-docz/src/theme/index'
import { merge } from 'lodash/fp'
import nightOwl from '@theme-ui/prism/presets/night-owl.json'

export default merge(baseTheme, {
  styles: {
    root: {
      fontSize: 2,
      color: 'text',
      bg: 'background',
    },
    blockquote: {
      fontStyle: "normal"
    },
    pre: {
      ...nightOwl
    }
  }
})