/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import React from 'react'
import { Message as SemanticMessage } from 'semantic-ui-react'
import ReactMarkdown from 'react-markdown'
import { Message as ThemeUIMessage } from 'theme-ui'

const Message = ({ title, description }) => {
  return (
    <ThemeUIMessage sx={{ bg: 'muted', my: 3 }}>
      <div sx={{ fontWeight: 'heading', fontSize: 2 }}>
        <span>{title}</span>
      </div>
      <ReactMarkdown source={description} />
    </ThemeUIMessage>
  )
}

export default Message
