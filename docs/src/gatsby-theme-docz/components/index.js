import React from "react";
import baseComponents from 'gatsby-theme-docz/src/components/index'
import ThemeUIPrism from "@theme-ui/prism"
import PrismCore from "prismjs/components/prism-core"
import "prismjs/components/prism-clike"
import "prismjs/components/prism-swift"
import "prismjs/components/prism-bash"
import "prismjs/components/prism-ruby"

export default {
  ...baseComponents,
  code: props => <ThemeUIPrism {...props} Prism={PrismCore} />,
}
