import prismTheme from '@theme-ui/prism/presets/night-owl.json'
import { system } from '@theme-ui/presets'
import { darken } from '@theme-ui/color'

// Breakpoints
const breakpoints = ['40em', '52em', '64em', '80em']
breakpoints.sm = breakpoints[0]
breakpoints.md = breakpoints[1]
breakpoints.lg = breakpoints[2]
breakpoints.xl = breakpoints[3]

// Radii
const radii = [0, 4, 8, 16]

// Space
const space = [0, 4, 8, 16, 32, 64, 128]
space.small = space[1]
space.medium = space[2]
space.large = space[3]

// Fonts
const fonts = {
  body: 'Inter, sans-serif',
  heading: 'Inter, sans-serif',
  monospace: 'Menlo, monospace',
}

// Font heights
const fontWeights = {
  body: 400,
  heading: 600,
  secondaryHeading: 600,
  bold: 700,
}

// Line heights
const lineHeights = {
  body: 1.925,
  heading: 1.125,
}

// Font sizes
const fontSizes = [12, 14, 16, 20, 24, 32, 48, 64]
fontSizes.body = fontSizes[2]
fontSizes.display = fontSizes[5]

// Heading
const heading = {
  fontWeight: 'secondaryHeading',
  fontFamily: 'heading',
  marginBottom: 3,
}

// Colors
const colors = {
  text: '#333333',
  background: '#fff',
  primary: '#3195E6',
  primaryAlpha: 'rgba(49,149,230, 0.1)',
  primaryComplementary: 'white',
  secondary: '#6F52DA',
  accent: '#64c4ed',
  muted: '#F2F2F2',
  // New colors
  gray1: '#333333',
  gray2: '#4F4F4F',
  gray3: '#828282',
  gray4: '#BDBDBD',
  gray5: '#E0E0E0',
  gray6: '#F2F2F2',
  red: '#E15554',
  blue: '#3195E6',
  orange: '#F2994A',
  yellow: '#E1BC29',
  green: '#3BB273',
  purple: '#6F52DA',
}

// Styles
const styles = {
  root: {
    color: 'gray2',
    fontFamily: 'body',
    lineHeight: 'body',
    fontWeight: 'body',
  },
  a: {
    color: 'secondary',
    backgroundImage: 'none',
    textShadow: 'none',
    '&:hover': {
      textDecoration: 'underline',
    },
    '&:focus': {
      textDecoration: 'underline',
    },
  },
  p: {
    fontFamily: 'body',
    mb: 3,
  },
  pre: {
    ...prismTheme,
    margin: 3,
    padding: 3,
    borderRadius: 2,
  },
  code: {
    fontSize: 0,
  },
  blockquote: {
    bg: 'muted',
    fontSize: 'body',
    borderLeft: '10px solid',
    borderLeftColor: 'primary',
    my: 3,
    py: 2,
    px: 3,
  },
  h1: {
    ...heading,
    fontWeight: 'heading',
    marginTop: 2,
    color: 'primary',
  },
  h2: {
    ...heading,
    marginTop: 4,
    color: 'gray1',
  },
  h3: {
    ...heading,
    marginTop: 4,
  },
  h4: {
    ...heading,
    fontWeight: 'body',
    marginTop: 3,
  },
  h5: {
    ...heading,
    fontWeight: 'body',
    marginTop: 3,
  },
  h6: {
    ...heading,
    fontWeight: 'body',
    marginTop: 3,
  },
  ul: {
    pl: 4,
    py: 3,
  },
}

export default {
  ...system,
  radii,
  breakpoints,
  fonts,
  space,
  fontSizes,
  fontWeights,
  lineHeights,
  styles,
  colors,
}
