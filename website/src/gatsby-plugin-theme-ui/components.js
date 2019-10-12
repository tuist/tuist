// src/gatsby-plugin-theme-ui/components.js
import React from "react";
import ThemeUIPrism from "@theme-ui/prism";
import PrismCore from "prismjs/components/prism-core";
import "prismjs/components/prism-clike";
import "prismjs/components/prism-swift";
import "prismjs/components/prism-bash";
import "prismjs/components/prism-ruby";

export default {
  pre: props => props.children,
  code: props => <ThemeUIPrism {...props} Prism={PrismCore} />
};
