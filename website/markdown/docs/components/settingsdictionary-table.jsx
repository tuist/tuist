import { Styled } from 'theme-ui'

import React from 'react'
import ReactMarkdown from 'react-markdown'

const SettingsDictionaryTable = ({ methods }) => {
  const headerStyle = `px-6 py-3 bg-gray-100 text-left text-xs leading-4 font-medium text-gray-600 uppercase tracking-wider`
  const cellStyle = `px-6 py-4 whitespace-normal leading-5 font-normal text-sm text-gray-900`

  return (
    <div className="my-2 py-2 sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8">
      <div className="align-middle inline-block min-w-full shadow sm:rounded-lg border-b border-gray-200">
        <table className="min-w-full divide-y divide-gray-200">
          <thead>
            <tr className="hidden md:table-row">
              <th className={headerStyle}>Subject</th>
              <th className={headerStyle}>Function Signature</th>
              <th className={headerStyle}>Description</th>
            </tr>
          </thead>

          <tbody>
            {methods.map((method, index) => {
              return (
                <tr
                  key={index}
                  className={`${index % 2 === 0 ? 'bg-white' : 'bg-gray-100'}`}
                >
                  <td className={`${cellStyle} hidden md:table-cell`}>
                    {method.subject}
                  </td>
                  <td className={`${cellStyle} hidden md:table-cell`}>
                    <Styled.inlineCode>{method.signature}</Styled.inlineCode>
                  </td>
                  <td className={`${cellStyle} hidden md:table-cell`}>
                    <ReactMarkdown source={method.description} />
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

export default SettingsDictionaryTable
