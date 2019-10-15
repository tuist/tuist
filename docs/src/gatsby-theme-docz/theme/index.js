import baseTheme from 'gatsby-theme-docz/src/theme/index'
import { merge } from 'lodash/fp'
import nightOwl from '@theme-ui/prism/presets/night-owl.json'

export default merge(baseTheme, {
  styles: {
    pre: {
      ...nightOwl
    }
  }
})