import React from 'react'
import { Message as SemanticMessage } from 'semantic-ui-react'
import ReactMarkdown from "react-markdown"

const Message = ({ title, description, success, warning, info, error }) => (
  <SemanticMessage
    success={success}
    warning={warning}
    info={info}
    error={error}
  >
    <SemanticMessage.Header>{title}</SemanticMessage.Header>
    <ReactMarkdown source={description}/>
  </SemanticMessage>
)

export default Message
