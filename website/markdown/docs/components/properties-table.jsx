import { jsx, Styled } from 'theme-ui'
import tw from 'twin.macro'
import React from 'react'
import ReactMarkdown from 'react-markdown'

const PropertiesTable = ({ properties }) => {
  const headerStyle = tw`px-6 py-3 bg-gray-100 text-left text-xs leading-4 font-medium text-gray-600 uppercase tracking-wider`
  const cellStyle = tw`px-6 py-4 whitespace-normal leading-5 font-normal text-sm text-gray-900`

  return (
    <div className="my-2 py-2 sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8">
      <div className="align-middle inline-block min-w-full shadow sm:rounded-lg border-b border-gray-200">
        <table css={[tw`min-w-full divide-y divide-gray-200`]}>
          <thead>
            <tr>
              <th css={[headerStyle, tw`hidden md:table-cell`]}>Property</th>
              <th css={[headerStyle, tw`hidden md:table-cell`]}>Description</th>
              <th css={[headerStyle, tw`hidden md:table-cell`]}>Type</th>
              <th css={[headerStyle, tw`hidden md:table-cell`]}>Optional</th>
              <th css={[headerStyle, tw`hidden md:table-cell`]}>Default</th>
            </tr>
          </thead>

          <tbody>
            {properties.map((prop, index) => {
              let type
              if (prop.typeLink) {
                type = <Styled.a href={prop.typeLink}>{prop.type}</Styled.a>
              } else {
                type = <span>{prop.type}</span>
              }

              const optionalValue = prop.optional ? 'Yes' : 'No'

              return (
                <tr
                  key={index}
                  css={[index % 2 == 0 ? tw`bg-white` : tw`bg-gray-100`]}
                >
                  <td css={[cellStyle]}>
                    <div css={[tw`font-bold md:font-normal`]}>{prop.name}</div>
                    <div css={[tw`block md:hidden`]}>
                      <ReactMarkdown source={prop.description} />
                    </div>
                    <div css={[tw`block md:hidden mt-3`]}>
                      <span css={[tw`font-medium`]}>Type: </span>{' '}
                      <Styled.inlineCode>{type}</Styled.inlineCode>
                    </div>
                    <div css={[tw`block md:hidden`]}>
                      <span css={[tw`font-medium`]}>Optional: </span>{' '}
                      {optionalValue}
                    </div>
                    <div css={[tw`block md:hidden`]}>
                      <span css={[tw`font-medium`]}>Default value: </span>{' '}
                      {prop.default != '' && (
                        <Styled.inlineCode>{prop.default}</Styled.inlineCode>
                      )}
                    </div>
                  </td>
                  <td css={[cellStyle, tw`hidden md:table-cell`]}>
                    <ReactMarkdown source={prop.description} />
                  </td>
                  <td css={[cellStyle, tw`hidden md:table-cell`]}>
                    <Styled.inlineCode>{type}</Styled.inlineCode>
                  </td>
                  <td css={[cellStyle, tw`hidden md:table-cell`]}>
                    {optionalValue}
                  </td>
                  <td css={[cellStyle, tw`hidden md:table-cell`]}>
                    {prop.default != '' && (
                      <Styled.inlineCode>{prop.default}</Styled.inlineCode>
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

export default PropertiesTable
