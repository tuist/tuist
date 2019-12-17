/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'

import React from 'react'
import { Label, Table } from 'semantic-ui-react'
import StyledCode from './styled-code'

const EnumTable = ({ cases }) => {
  const borderStyle = {
    border: theme => `1px solid ${theme.colors.gray5}`,
    borderCollapse: 'collapse',
  }
  const cellStyle = {
    ...borderStyle,
    p: 2,
  }
  return (
    <table sx={{ ...borderStyle }}>
      <thead>
        <tr sx={{ bg: 'gray6' }}>
          <th sx={{ ...cellStyle }}>Case</th>
          <th sx={{ ...cellStyle }}>Description</th>
        </tr>
      </thead>

      <tbody>
        {cases.map((prop, index) => {
          return (
            <tr key={index}>
              <td sx={{ ...cellStyle }}>
                <Styled.code>{prop.case}</Styled.code>
              </td>
              <td sx={{ ...cellStyle }}>{prop.description}</td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

export default EnumTable
