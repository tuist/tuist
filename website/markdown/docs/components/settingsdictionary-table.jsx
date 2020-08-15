import { Styled } from 'theme-ui'
import tw from 'twin.macro'

import React from 'react'
import ReactMarkdown from 'react-markdown'

const SettingsDictionaryTable = ({ methods }) => {
  const headerStyle = tw`px-6 py-3 bg-gray-100 text-left text-xs leading-4 font-medium text-gray-600 uppercase tracking-wider`
  const cellStyle = tw`px-6 py-4 whitespace-normal leading-5 font-normal text-sm text-gray-900`

  return (
    <div className="my-2 py-2 sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8">
      <div className="align-middle inline-block min-w-full shadow sm:rounded-lg border-b border-gray-200">
        <table css={[tw`min-w-full divide-y divide-gray-200`]}>
          <thead>
            <tr css={[tw`hidden md:table-row`]}>
              <th css={[headerStyle]}>Subject</th>
              <th css={[headerStyle]}>Function Signature</th>
              <th css={[headerStyle]}>Description</th>
            </tr>
          </thead>

          <tbody>
            {methods.map((method, index) => {
              return (
                <tr
                  key={index}
                  css={[index % 2 == 0 ? tw`bg-white` : tw`bg-gray-100`]}
                >
                  <td css={[cellStyle, tw`hidden md:table-cell`]}>
                    {method.subject}
                  </td>
                  <td css={[cellStyle, tw`hidden md:table-cell`]}>
                    <Styled.inlineCode>{method.signature}</Styled.inlineCode>
                  </td>
                  <td css={[cellStyle, tw`hidden md:table-cell`]}>
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
