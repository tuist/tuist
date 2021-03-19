/** @jsx jsx */

import { jsx, Styled } from 'theme-ui'
import React, { useState } from 'react'
import ThemeUIPrism from '@theme-ui/prism'
import PrismCore from 'prismjs/components/prism-core'
import 'prismjs/components/prism-clike'
import 'prismjs/components/prism-swift'
import 'prismjs/components/prism-c'
import 'prismjs/components/prism-objectivec'
import 'prismjs/components/prism-bash'
import 'prismjs/components/prism-ruby'
import copy from 'copy-text-to-clipboard'

export default ({ showCopy = true, my = 25, bg, ...props }) => {
  const defaultCopyContent = 'Copy the content'
  const [copyContent, setCopyContent] = useState(defaultCopyContent)
  let style = { m: 0 }
  if (bg) {
    style.bg = bg
  }
  return (
    <div sx={{ my: my, display: 'flex', flexDirection: 'column' }}>
      <ThemeUIPrism {...props} Prism={PrismCore} sx={style} />
      {showCopy && (
        <div
          sx={{
            alignSelf: 'flex-end',
            fontSize: 1,
            color: 'secondary',
            cursor: 'pointer',
          }}
          onClick={() => {
            setCopyContent('Copied')
            copy(props.children)
            setTimeout(() => {
              setCopyContent(defaultCopyContent)
            }, 1000)
          }}
        >
          {copyContent}
        </div>
      )}
    </div>
  )
}
