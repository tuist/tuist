import React from 'react'
import ReactMarkdown from 'react-markdown'

const renderers = {
  link: (props) => <a className="underline hover:text-blue-600" {...props} />,
}

const RecommendationsTable = ({ recommendations }) => {
  return (
    <table className="table-auto my-5 w-full">
      <tbody>
        {recommendations.map((recommendation, index) => {
          let className = ''
          if (index % 2 === 0) {
            className = `${className} bg-gray-100`
          }
          return (
            <tr key={recommendation.name} className={className}>
              <td className="p-3">
                <b>{recommendation.name}</b>
              </td>
              <td className="p-3">
                <ReactMarkdown
                  source={recommendation.value}
                  renderers={renderers}
                />
              </td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

export default RecommendationsTable
