import { createCss } from '@stitches/react'

export const {
  styled,
  css,
  global,
  keyframes,
  getCssString,
  theme,
} = createCss({
  //https://system-ui.com/theme
  theme: {
    colors: {
      text: '#000',
      background: '#fff',
      primary: '#07c',
      secondary: '#30c',
      muted: '#f6f6f6',
    },
    space: {
      1: '0px',
      2: '4px',
      3: '8px',
      4: '16px',
      5: '32px',
      6: '64px',
      7: '128px',
      8: '256px',
      9: '512px',
    },
    fontSizes: {
      1: '12px',
      2: '14px',
      3: '16px',
      4: '20px',
      5: '24px',
      6: '32px',
      7: '48px',
      8: '64px',
      9: '96px',
    },
    fonts: {
      body:
        'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif',
      heading: 'inherit',
      monospace: 'Menlo, monospace',
    },
    fontWeights: {
      body: 400,
      heading: 700,
      bold: 700,
    },
    lineHeights: {
      body: 1.5,
      heading: 1.125,
    },
    letterSpacings: {},
    sizes: {},
    borderWidths: {},
    borderStyles: {},
    radii: {},
    shadows: {},
    zIndices: {},
    transitions: {},
  },
  media: {},
  utils: {},
  prefix: '',
  themeMap: {},
})
