import oceanBeachTheme from "typography-theme-ocean-beach";
import { toTheme } from "@theme-ui/typography";
import prismTheme from "@theme-ui/prism/presets/night-owl.json";

// Breakpoints
const breakpoints = ["40em", "52em", "64em", "80em"];
breakpoints.sm = breakpoints[0];
breakpoints.md = breakpoints[1];
breakpoints.lg = breakpoints[2];
breakpoints.xl = breakpoints[3];

// Radii
const radii = [0, 4, 8, 16];

// Space
const space = [0, 4, 8, 16, 32, 64, 128];
space.small = space[1];
space.medium = space[2];
space.large = space[3];

// Fonts
const fonts = {};
fonts.body = [
  "-apple-system",
  "system-ui",
  "Helvetica Neue",
  "Helvetica",
  "Arial",
  "Verdana",
  "sans-serif"
];
fonts.heading = fonts.body;

// Font sizes
const fontSizes = [12, 14, 16, 20, 24, 32];
fontSizes.body = fontSizes[2];
fontSizes.display = fontSizes[5];

export default {
  ...toTheme(oceanBeachTheme),
  radii,
  breakpoints,
  fonts,
  space,
  fontSizes,
  fontWeights: {
    body: 400,
    heading: 700,
    bold: 700
  },
  lineHeights: {
    body: 1.5,
    heading: 1.125
  },
  styles: {
    pre: {
      ...prismTheme,
      padding: 3,
      borderRadius: 2
    },
    code: {
      fontSize: 1
    },
    blockquote: {
      bg: "secondary",
      fontSize: 3,
      py: 2,
      px: 3,
      color: "background"
    },
    h1: {
      marginTop: 1,
      color: "primary"
    },
    h2: {
      marginTop: 3,
      color: "secondary"
    },
    h3: {
      color: "secondary"
    }
  },
  initialColorMode: "light",
  useCustomProperties: true,
  colors: {
    text: "#000",
    background: "#fff",
    primary: "#12344F",
    primaryComplementary: "white",
    secondary: "#7768AF",
    accent: "#64c4ed",
    muted: "#F8F8F8",
    modes: {
      dark: {
        text: "white",
        background: "#181818",
        primary: "#17223b",
        primaryComplementary: "white",
        secondary: "#ffb5b5",
        accent: "#c83660",
        muted: "#F8F8F8"
      },
      spring: {
        text: "white",
        background: "#60a9a6",
        primary: "#226b80",
        primaryComplementary: "#f5fec0",
        secondary: "#fafdcb",
        accent: "#f6d365",
        muted: "#F8F8F8"
      },
      mandarine: {
        primary: "#ea9010",
        primaryComplementary: "white",
        background: "#2e294e",
        text: "#fcfafa",
        secondary: "#fbc99d",
        accent: "#f6d365",
        muted: "#F8F8F8"
      }
    }
  }
};
