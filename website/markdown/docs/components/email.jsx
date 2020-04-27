import React from 'react'
import Mailto from 'react-protected-mailto'

export default ({ email, subject }) => (
  <Mailto
    email={email}
    headers={{ subject: subject != null ? subject : 'Question about Tuist' }}
  />
)
