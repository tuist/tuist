/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import React from 'react'
import ReactMarkdown from 'react-markdown'
import tw from 'twin.macro'

const Message = ({ title, description, info, warning }) => {
  let backgroundColor
  let iconColor
  let titleColor
  let textColor
  if (info) {
    backgroundColor = tw`bg-blue-100`
    iconColor = tw`text-blue-400`
    titleColor = tw`text-blue-800`
    textColor = tw`text-blue-700`
  }
  if (warning) {
    backgroundColor = tw`bg-yellow-100`
    iconColor = tw`text-yellow-400`
    titleColor = tw`text-yellow-800`
    textColor = tw`text-yellow-700`
  }

  return (
    <div className="my-3">
      <div className="rounded-md p-4" css={[backgroundColor]}>
        <div className="flex">
          <div className="flex-shrink-0">
            <svg
              css={[iconColor, tw`h-5 w-5`, warning ? tw`block` : tw`hidden`]}
              viewBox="0 0 20 20"
              fill="currentColor"
            >
              <path
                fill-rule="evenodd"
                d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
                clip-rule="evenodd"
              />
            </svg>
            <svg
              css={[iconColor, tw`h-5 w-5`, info ? tw`block` : tw`hidden`]}
              viewBox="0 0 20 20"
              fill="currentColor"
            >
              <path
                fill-rule="evenodd"
                d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
                clip-rule="evenodd"
              />
            </svg>
          </div>
          <div className="ml-3">
            <h3 className="text-sm leading-5 font-medium" css={[titleColor]}>
              {title}
            </h3>
            <div className="mt-2 text-sm leading-5" css={[textColor]}>
              <ReactMarkdown source={description} />
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default Message
