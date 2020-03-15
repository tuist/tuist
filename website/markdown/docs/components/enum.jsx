/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import ReactMarkdown from 'react-markdown'

const EnumTable = ({ cases }) => {
  const borderStyle = {
    border: theme => `1px solid ${theme.colors.gray}`,
    borderCollapse: 'collapse',
  }
  const cellStyle = {
    ...borderStyle,
    p: 2,
  }
  return (
    <table sx={{ ...borderStyle, tableLayout: 'fixed', my: 3 }}>
      <thead sx={{ display: ['none', 'table-header-group'] }}>
        <tr sx={{ bg: 'muted' }}>
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
                <p sx={{ display: ['block', 'none'] }}>
                  <ReactMarkdown source={prop.description} />
                </p>
              </td>
              <td
                sx={{
                  ...cellStyle,
                  display: ['none', 'table-cell'],
                }}
              >
                <ReactMarkdown source={prop.description} />
              </td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

export default EnumTable
