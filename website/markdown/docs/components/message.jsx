/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import React from 'react'
import { Message as SemanticMessage } from 'semantic-ui-react'
import ReactMarkdown from 'react-markdown'

const Message = ({ title, description, success, warning, info, error }) => {
  let color = 'primary'
  let prefix = ''
  if (success) {
    color = 'green'
  } else if (warning) {
    color = 'yellow'
    prefix = 'Warning'
  } else if (error) {
    color = 'red'
  } else if (info) {
    color = 'primary'
    prefix = 'Information'
  }
  return (
    <div sx={{ bg: 'gray6', display: 'flex', flexDirection: 'row', my: 2 }}>
      <div sx={{ width: '10px', bg: color }} />
      <div sx={{ flex: 1, p: 3 }}>
        <div sx={{ fontWeight: 'heading', fontSize: 2 }}>
          {prefix != '' && (
            <span sx={{ mr: 1, color: color }}>{`${prefix} - `}</span>
          )}
          <span>{title}</span>
        </div>
        <ReactMarkdown source={description} />
      </div>
    </div>
  )
}

export default Message
