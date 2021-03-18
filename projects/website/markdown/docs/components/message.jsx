/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import React from 'react'
import ReactMarkdown from 'react-markdown'

const Message = ({ title, description, info, warning }) => {
  let backgroundColor
  let iconColor
  let titleColor
  let textColor
  if (info) {
    backgroundColor = `bg-blue-100`
    iconColor = `text-blue-400`
    titleColor = `text-blue-800`
    textColor = `text-blue-700`
  }
  if (warning) {
    backgroundColor = `bg-yellow-100`
    iconColor = `text-yellow-400`
    titleColor = `text-yellow-800`
    textColor = `text-yellow-700`
  }

  return (
    <div className="my-6">
      <div className={`${backgroundColor} rounded-md p-4`}>
        <div className="flex">
          <div className="flex-shrink-0">
            <svg
              className={`${iconColor} h=5 w-5 ${warning ? 'block' : 'hidden'}`}
              viewBox="0 0 20 20"
              fill="currentColor"
            >
              <path
                fillRule="evenodd"
                d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
                clipRule="evenodd"
              />
            </svg>
            <svg
              className={`${iconColor} h-5 w-5 ${info ? 'block' : 'hidden'}`}
              viewBox="0 0 20 20"
              fill="currentColor"
            >
              <path
                fillRule="evenodd"
                d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
                clipRule="evenodd"
              />
            </svg>
          </div>
          <div className="ml-3">
            <h3 className={`${titleColor} text-sm leading-5 font-medium`}>
              {title}
            </h3>
            <div className={`${textColor} mt-2 text-sm leading-5`}>
              <ReactMarkdown source={description} />
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default Message
