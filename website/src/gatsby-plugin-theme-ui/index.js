import prismTheme from '@theme-ui/prism/presets/night-owl.json'
import { system } from '@theme-ui/presets'
import prism from '@theme-ui/prism/presets/theme-ui'

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

// Colors
const colors = {
  text: "#000",
  background: "#fff",
  primary: "#046abd",
  secondary: "#6F52DA",
  accent: "hsl(280, 100%, 57%)",
  muted: "#f9f9fc",
  gray: "#555",
  modes: {
    black: {
      text: "#fff",
      background: "#000",
      primary: "#0ff",
      secondary: "#0fc",
      accent: "#f0f",
      muted: "#111",
      gray: "#888",
    },
    dark: {
      text: "#fff",
      background: "hsl(180, 5%, 15%)",
      primary: "hsl(180, 100%, 57%)",
      secondary: "hsl(50, 100%, 57%)",
      accent: "hsl(310, 100%, 57%)",
      muted: "hsl(180, 5%, 5%)",
      gray: "hsl(180, 0%, 70%)",
    },
    deep: {
      text: "#fff",
      background: "hsl(230,25%,18%)",
      primary: "hsl(260, 100%, 80%)",
      secondary: "hsl(290, 100%, 80%)",
      accent: "hsl(290, 100%, 80%)",
      muted: "hsla(230, 20%, 0%, 20%)",
      gray: "hsl(210, 50%, 60%)",
    },
    hack: {
      text: "hsl(120, 100%, 75%)",
      background: "hsl(120, 20%, 10%)",
      primary: "hsl(120, 100%, 40%)",
      secondary: "hsl(120, 50%, 40%)",
      accent: "hsl(120, 100%, 90%)",
      muted: "hsl(120, 20%, 7%)",
      gray: "hsl(120, 20%, 40%)",
    },
    pink: {
      text: "hsl(350, 80%, 10%)",
      background: "hsl(350, 100%, 90%)",
      primary: "hsl(350, 100%, 50%)",
      secondary: "hsl(280, 100%, 50%)",
      accent: "hsl(280, 100%, 20%)",
      muted: "hsl(350, 100%, 88%)",
      gray: "hsl(350, 40%, 50%)",
    },
  },
}

// Styles
const styles = {
  root: {
    fontFamily: "body",
    lineHeight: "body",
    fontSize: 2,
    transitionProperty: "background-color",
    transitionTimingFunction: "ease-out",
    transitionDuration: ".4s",
  },
  a: {
    color: "primary",
    ":hover,:focus": {
      color: "secondary",
    },
  },
  h1: {
    variant: "text.heading",
    mb: 4,
    mt: 4
  },
  h2: {
    mt: 4,
    mb: 4,
    variant: "text.heading",
  },
  h3: {
    my: 3,
    variant: 'text.heading',
    fontSize: 2,
  },
  h4: {
    my: 3,
    variant: "text.heading",
  },
  h5: {
    my: 3,
    variant: "text.heading",
  },
  h6: {
    my: 3,
    variant: "text.heading",
  },
  img: {
    maxWidth: "100%",
    height: "auto",
  },
  pre: {
    fontFamily: "monospace",
    fontSize: 1,
    bg: "muted",
    p: 3,
    borderRadius: 8,
    overflowX: "auto",
    variant: "prism",
  },
  code: {
    fontFamily: "monospace",
    color: "secondary",
  },
  inlineCode: {
    fontFamily: "monospace",
    color: "secondary",
  },
  hr: {
    border: 0,
    my: 4,
    borderBottom: "1px solid",
    borderColor: "muted",
  },
  table: {
    width: "100%",
    borderCollapse: "separate",
    borderSpacing: 0,
  },
  th: {
    textAlign: "left",
    py: 2,
    borderBottomStyle: "solid",
  },
  td: {
    textAlign: "left",
    py: 2,
    borderBottom: "1px solid",
    borderColor: "muted",
  },
  blockquote: {
    fontWeight: "bold",
    mx: 0,
    px: 3,
    my: 5,
    borderLeft: "4px solid",
  },
  div: {
    "&.footnotes": {
      variant: "text.small",
    },
  },
  navlink: {
    color: "inherit",
    textDecoration: "none",
    ":hover,:focus": {
      color: "primary",
    },
  },
  navitem: {
    variant: "styles.navlink",
    display: "inline-flex",
    alignItems: "center",
    fontWeight: "bold",
  },
}

const text = {
  heading: {
    fontSize: 4,
    fontWeight: "heading",
    lineHeight: "heading",
  },
  small: {
    fontSize: 0,
  },
  header: {
    textDecoration: 'none',
    color: 'text',
    "&:hover": {
      color: 'primary'
    }
  },
  "gatsby-link": {
    textDecoration: 'none',
    color: 'primary',
    "&:hover": {
      color: 'secondary'
    }
  }
}

export default {
  ...system,
  radii,
  breakpoints,
  fonts,
  space,
  fontSizes,
  text,
  fontWeights,
  lineHeights,
  prism,
  styles,
  colors,
}
