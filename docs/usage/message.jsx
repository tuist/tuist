import React from 'react'
import { Message as SemanticMessage } from 'semantic-ui-react'

const Message = ({ title, description, success, warning, info, error }) => (
  <SemanticMessage
    success={success}
    warning={warning}
    info={info}
    error={error}
  >
    <SemanticMessage.Header>{title}</SemanticMessage.Header>
    <p>{description}</p>
  </SemanticMessage>
)

export default Message
