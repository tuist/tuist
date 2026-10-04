# Public documentation rendering

`AtlasWeb.Docs.Markdown` compiles trusted documentation source into sanitized markup. It renders fenced code through the snippet markup adapted from Tuist and Markdown admonitions through Noora alerts. Keep code escaped and copy source independent of presentation. Inline code and snippet styles use Noora tokens in the documentation bundle.

The public controller does not start a live session. The copy-page dropdown uses the actual Noora component and its menu runtime, mounting its portal on these static pages. Preserve keyboard navigation, clipboard feedback, and the plain-text source route when changing this behavior.

Markdown tables use the same Noora wrapper, scroll regions, and table runtime as Tuist documentation. Preserve inline markup and native horizontal scrolling on narrow screens. The header copies Tuist’s Noora theme and primary action buttons for desktop and mobile, including its neutral GitHub icon link to Atlas’s source directory.
