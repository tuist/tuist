import prismTheme from '@theme-ui/prism/presets/night-owl.json'
import { tailwind } from '@theme-ui/presets'

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

// Colors
const colors = {
  text: '#2d3748', // text-gray-800
  background: '#ffffff',
  primary: '#046abd',
  secondary: '#6F52DA',
  accent: '#b624ff',
  muted: '#f9f9fc',
  gray: '#555',
}

// Styles
const styles = {
  ...tailwind.styles,
  root: {
    fontFamily: 'body',
    lineHeight: 'body',
    fontSize: 2,
    transitionProperty: 'background-color',
    transitionTimingFunction: 'ease-out',
    transitionDuration: '.4s',
  },
  ul: {
    py: 3,
    pl: 4,
  },
  ol: {
    pl: 4,
  },
  a: {
    color: 'primary',
    ':hover,:focus,:visited': {
      color: 'secondary',
    },
  },
  h1: {
    variant: 'text.heading',
    mt: 5,
    fontSize: [5, 6],
  },
  h2: {
    color: 'text',
    mt: 5,
    variant: 'text.heading',
    fontSize: 5,
  },
  h3: {
    color: 'text',
    my: 4,
    variant: 'text.heading',
    fontSize: 4,
  },
  h4: {
    color: 'text',
    my: 3,
    variant: 'text.heading',
    fontSize: 3,
  },
  h5: {
    color: 'text',
    my: 3,
    variant: 'text.heading',
    fontSize: 2,
  },
  h6: {
    my: 3,
    variant: 'text.heading',
    fontSize: 2,
  },
  img: {
    maxWidth: '100%',
    height: 'auto',
  },
  p: {
    mt: 3,
  },
  pre: {
    fontFamily: 'monospace',
    fontSize: 1,
    bg: 'muted',
    p: 3,
    borderRadius: 8,
    overflowX: 'auto',
    variant: 'prism',
  },
  code: {
    fontFamily: 'monospace',
    color: 'secondary',
    ...prismTheme,
  },
  li: {
    listStyleType: 'circle',
  },
  inlineCode: {
    fontSize: 1,
    fontFamily: 'monospace',
    color: 'primary',
  },
  hr: {
    border: 0,
    my: 4,
    borderBottom: '1px solid',
    borderColor: 'muted',
  },
  table: {
    width: '100%',
    borderCollapse: 'separate',
    borderSpacing: 0,
  },
  th: {
    textAlign: 'left',
    py: 2,
    borderBottomStyle: 'solid',
  },
  td: {
    textAlign: 'left',
    py: 2,
    borderBottom: '1px solid',
    borderColor: 'muted',
  },
  blockquote: {
    fontWeight: 'bold',
    mx: 0,
    px: 3,
    my: 5,
    borderLeft: '4px solid',
  },
  div: {
    '&.footnotes': {
      variant: 'text.small',
    },
  },
  navlink: {
    color: 'inherit',
    textDecoration: 'none',
    ':hover,:focus': {
      color: 'primary',
    },
  },
  navitem: {
    variant: 'styles.navlink',
    display: 'inline-flex',
    alignItems: 'center',
    fontWeight: 'bold',
  },
}

const text = {
  heading: {
    fontSize: 4,
    fontWeight: 'heading',
    lineHeight: 'heading',
  },
  small: {
    fontSize: 0,
  },
  header: {
    textDecoration: 'none',
    color: 'text',
    '&:hover': {
      color: 'primary',
    },
  },
  'gatsby-link': {
    textDecoration: 'none',
    color: 'primary',
    '&:hover': {
      color: 'secondary',
    },
  },
}

export default {
  ...tailwind,
  radii,
  breakpoints,
  space,
  fontSizes,
  text,
  fontWeights,
  lineHeights,
  // prism,
  styles,
  colors,
}
