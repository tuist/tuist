/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'

import React from 'react'
import ReactMarkdown from 'react-markdown'

const SettingsDictionaryTable = ({ methods }) => {
  const borderStyle = {
    border: theme => `1px solid ${theme.colors.gray}`,
    borderCollapse: 'collapse',
  }
  const cellStyle = {
    ...borderStyle,
    p: 2,
  }
  return (
    <table
      sx={{
        ...borderStyle,
        my: 3,
      }}
    >
      <thead>
        <tr sx={{ bg: 'muted', ...borderStyle, display: ['none', 'table-row'] }}>
          <th sx={{ ...cellStyle }}>Subject</th>
          <th sx={{ ...cellStyle }}>Function Signature</th>
          <th sx={{ ...cellStyle }}>Description</th>
        </tr>
      </thead>

      <tbody>
        {methods.map((method, index) => {
          return (
            <tr key={index} sx={{ ...borderStyle }}>
              <td sx={{ ...cellStyle, display: ['none', 'table-cell'] }}>
                {method.subject}
              </td>
              <td sx={{ ...cellStyle, display: ['none', 'table-cell'] }}>
                <Styled.code>{method.signature}</Styled.code>
              </td>
              <td sx={{ ...cellStyle, display: ['none', 'table-cell'], mt: 6 }}>
                <ReactMarkdown source={method.description} />
              </td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

export default SettingsDictionaryTable
