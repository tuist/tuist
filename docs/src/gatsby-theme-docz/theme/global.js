import baseGlobal from 'gatsby-theme-docz/src/theme/global'

export default {
  ...baseGlobal,
  ".ui.info.message": {
    fontSize: (theme) => theme.fontSize[0],
  },
  "pre[class*='language-']": {
    overflow: "auto",
  },
  "div[class*='token-line']": {
    overflowWrap: "normal",
  },
}
