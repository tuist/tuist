/** @jsx jsx */

import { jsx, Styled } from 'theme-ui'
import React from 'react'
import Code from './code'

const heading = Tag => props => {
  if (!props.id) return <Tag {...props} />
  return (
    <Tag {...props}>
      <a href={`#${props.id}`}>{props.children}</a>
    </Tag>
  )
}

export default {
  pre: ({ children }) => {
    return <div>{children}</div>
  },
  code: props => <Code {...props} />,
  h1: heading('h1'),
  h2: heading('h2'),
  h3: heading('h3'),
  h4: heading('h4'),
  h5: heading('h5'),
  h6: heading('h6'),
}
