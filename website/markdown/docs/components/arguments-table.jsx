import { jsx, Styled } from 'theme-ui'
import tw from 'twin.macro'
import React from 'react'
import ReactMarkdown from 'react-markdown'

const ArgumentsTable = ({ args }) => {
  const headerStyle = tw`px-6 py-3 bg-gray-100 text-left text-xs leading-4 font-medium text-gray-600 uppercase tracking-wider`
  const cellStyle = tw`px-6 py-4 whitespace-normal leading-5 font-normal text-sm text-gray-900`

  return (
    <div className="my-2 py-2 sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8">
      <div className="align-middle inline-block min-w-full shadow sm:rounded-lg border-b border-gray-200">
        <table css={[tw`min-w-full divide-y divide-gray-200`]}>
          <thead>
            <tr>
              <th css={[headerStyle, tw`hidden md:table-cell`]}>Argument</th>
              <th css={[headerStyle, tw`hidden md:table-cell`]}>Short</th>
              <th css={[headerStyle, tw`hidden md:table-cell`]}>Description</th>
              <th css={[headerStyle, tw`hidden md:table-cell`]}>Values</th>
              <th css={[headerStyle, tw`hidden md:table-cell`]}>Default</th>
            </tr>
          </thead>

          <tbody>
            {args.map((arg, index) => {
              const optionalValue = arg.optional ? 'Yes' : 'No'

              return (
                <tr
                  key={index}
                  css={[index % 2 == 0 ? tw`bg-white` : tw`bg-gray-100`]}
                >
                  <td css={[cellStyle]}>
                    <div css={[tw`font-bold md:font-normal`]}>
                      <ReactMarkdown source={arg.long} />
                    </div>
                    <div css={[tw`block md:hidden`]}>
                      <ReactMarkdown source={arg.short} />
                    </div>
                    {/* <div css={[tw`block md:hidden mt-3`]}>
                      <span css={[tw`font-medium`]}>Type: </span>{' '}
                      <Styled.inlineCode>{type}</Styled.inlineCode>
                    </div> */}
                    <div css={[tw`block md:hidden`]}>
                      <span css={[tw`font-medium`]}>Optional: </span>{' '}
                      {optionalValue}
                    </div>
                    <div css={[tw`block md:hidden`]}>
                      <span css={[tw`font-medium`]}>Default value: </span>{' '}
                      {arg.default != '' && (
                        <Styled.inlineCode>{arg.default}</Styled.inlineCode>
                      )}
                    </div>
                  </td>
                  <td css={[cellStyle, tw`hidden md:table-cell`]}>
                    <ReactMarkdown source={arg.short} />
                  </td>
                  <td css={[cellStyle, tw`hidden md:table-cell`]}>
                    <ReactMarkdown source={arg.description} />
                  </td>
                  <td css={[cellStyle, tw`hidden md:table-cell`]}>
                    {arg.values && (
                      <ReactMarkdown source={arg.values.join(', ')} />
                    )}
                  </td>
                  <td css={[cellStyle, tw`hidden md:table-cell`]}>
                    {arg.default != '' && (
                      <ReactMarkdown source={arg.default} />
                    )}
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

export default ArgumentsTable
