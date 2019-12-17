/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'

import React from 'react'
import ReactMarkdown from 'react-markdown'

const PropertiesTable = ({ properties }) => {
  const borderStyle = {
    border: theme => `1px solid ${theme.colors.gray5}`,
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
      }}
    >
      <tr sx={{ bg: 'gray6', ...borderStyle }}>
        <th sx={{ ...cellStyle }}>Property</th>
        <th sx={{ ...cellStyle }}>Description</th>
        <th sx={{ ...cellStyle }}>Type</th>
        <th sx={{ ...cellStyle }}>Optional</th>
        <th sx={{ ...cellStyle }}>Default</th>
      </tr>

      <tbody>
        {properties.map((prop, index) => {
          let type
          if (prop.typeLink) {
            type = <a href={prop.typeLink}>{prop.type}</a>
          } else {
            type = <span>{prop.type}</span>
          }

          const optionalValue = prop.optional ? 'Yes' : 'No'

          return (
            <tr key={index} sx={{ ...borderStyle }}>
              <td sx={{ ...cellStyle }}>{prop.name}</td>
              <td sx={{ ...cellStyle }}>
                <ReactMarkdown source={prop.description} />
              </td>
              <td sx={{ ...cellStyle }}>
                <Styled.code>{type}</Styled.code>
              </td>
              <td sx={{ ...cellStyle }}>{optionalValue}</td>
              <td sx={{ ...cellStyle }}>
                {prop.default != '' && (
                  <Styled.code>{prop.default}</Styled.code>
                )}
              </td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

export default PropertiesTable
