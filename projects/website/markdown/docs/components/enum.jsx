import React from 'react'
import { Styled } from 'theme-ui'
import ReactMarkdown from 'react-markdown'

const EnumTable = ({ cases }) => {
  const headerStyle = `px-6 py-3 bg-gray-100 text-left text-xs leading-4 font-medium text-gray-600 uppercase tracking-wider`
  const cellStyle = `px-6 py-4 whitespace-normal leading-5 font-normal text-sm text-gray-900`

  return (
    <div className="my-2 py-2 sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8">
      <div className="align-middle inline-block min-w-full shadow sm:rounded-lg border-b border-gray-200">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="hidden md:table-header-group">
            <tr>
              <th className={`${headerStyle} hidden md:table-cell`}>Case</th>
              <th className={`${headerStyle} hidden md:table-cell`}>
                Description
              </th>
            </tr>
          </thead>

          <tbody>
            {cases.map((prop, index) => {
              return (
                <tr key={index}>
                  <td className={cellStyle}>
                    <Styled.inlineCode>{prop.case}</Styled.inlineCode>
                    <div className="block mt-2 md:mt-0 md:hidden">
                      <ReactMarkdown source={prop.description} />
                    </div>
                  </td>
                  <td className="hidden md:table-cell">
                    <ReactMarkdown source={prop.description} />
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}

export default EnumTable
