/** @jsx jsx */

import { jsx, Styled } from 'theme-ui'
import React from 'react'
import Code from './code'
import Message from '../../markdown/docs/components/message'
import Email from '../../markdown/docs/components/email'

const heading = (Tag) => (props) => {
  if (!props.id) return <Tag {...props} />
  return (
    <Styled.a sx={{ textDecoration: 'none' }} href={`#${props.id}`}>
      <Tag {...props}>{props.children}</Tag>
    </Styled.a>
  )
}

export default {
  pre: ({ children }) => {
    return <div>{children}</div>
  },
  code: (props) => <Code {...props} />,
  h1: heading('h1'),
  h2: heading('h2'),
  h3: heading('h3'),
  h4: heading('h4'),
  h5: heading('h5'),
  h6: heading('h6'),
  Message: Message,
  Email: Email,
}
