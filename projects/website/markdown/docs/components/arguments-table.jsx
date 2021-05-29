import React from 'react'
import ReactMarkdown from 'react-markdown'

const ArgumentsTable = ({ args }) => {
  const headerStyle = `px-6 py-3 bg-gray-100 text-left text-xs leading-4 font-medium text-gray-600 uppercase tracking-wider`
  const cellStyle = `px-6 py-4 whitespace-normal leading-5 font-normal text-sm text-gray-900`

  return (
    <div className="my-2 py-2 sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8">
      <div className="align-middle inline-block min-w-full shadow sm:rounded-lg border-b border-gray-200">
        <table className="min-w-full divide-y divide-gray-200">
          <thead>
            <tr>
              <th className={`${headerStyle} hidden md:table-cell`}>
                Argument
              </th>
              <th className={`${headerStyle} hidden md:table-cell`}>Short</th>
              <th className={`${headerStyle} hidden md:table-cell`}>
                Description
              </th>
              <th className={`${headerStyle} hidden md:table-cell`}>Values</th>
              <th className={`${headerStyle} hidden md:table-cell`}>Default</th>
              <th className={`${headerStyle} hidden md:table-cell`}>
                Required
              </th>
            </tr>
          </thead>

          <tbody>
            {args.map((arg, index) => {
              const optionalValue = arg.optional ? 'Yes' : 'No'

              return (
                <tr
                  key={index}
                  className={`${index % 2 == 0 ? 'bg-white' : 'bg-gray-100'}`}
                >
                  <td className={cellStyle}>
                    <div className="font-bold md:font-normal">
                      <ReactMarkdown source={arg.long} />
                    </div>
                    <div className="block md:hidden font-bold">
                      <ReactMarkdown source={arg.short} />
                    </div>
                    <div className="block md:hidden">
                      <span className="font-semibold mt-3 uppercase">
                        Description:{' '}
                      </span>{' '}
                      <ReactMarkdown source={arg.description} />
                    </div>
                    {arg.values && (
                      <div className="block md:hidden mt-3">
                        <span className="font-semibold uppercase">
                          Values:{' '}
                        </span>{' '}
                        <ReactMarkdown source={arg.values.join(', ')} />
                      </div>
                    )}
                    {arg.default && (
                      <div className="block md:hidden mt-3">
                        <span className="font-semibold uppercase">
                          Default:{' '}
                        </span>{' '}
                        <ReactMarkdown source={arg.default} />
                      </div>
                    )}
                  </td>
                  <td className={`${cellStyle} hidden md:table-cell`}>
                    <ReactMarkdown source={arg.short} />
                  </td>
                  <td className={`${cellStyle} hidden md:table-cell`}>
                    <ReactMarkdown source={arg.description} />
                  </td>
                  <td className={`${cellStyle} hidden md:table-cell`}>
                    {arg.values && (
                      <ReactMarkdown source={arg.values.join(', ')} />
                    )}
                  </td>
                  <td className={`${cellStyle} hidden md:table-cell`}>
                    {arg.default != '' && (
                      <ReactMarkdown source={arg.default} />
                    )}
                  </td>
                  <td className={`${cellStyle} hidden md:table-cell`}>
                    {arg.required === true ? 'Yes' : 'No'}
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
