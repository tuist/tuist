/** @jsx jsx */
import { jsx } from '@emotion/core'
import React from 'react'
import { Link } from 'gatsby'
import tw from 'twin.macro'
import { useCookies } from 'react-cookie'

const CookieBanner = () => {
  const cookieName = 'cookie-banner'
  const [cookies, setCookie] = useCookies([cookieName])

  if (cookies[cookieName]) {
    return <div />
  } else {
    return (
      <div className="fixed bottom-0 inset-x-0 pb-2 sm:pb-5 z-10">
        <div className="max-w-screen-xl mx-auto px-2 sm:px-6 lg:px-8">
          <div className="p-2 rounded-lg bg-blue-600 shadow-lg sm:p-3">
            <div className="flex items-center justify-between flex-wrap">
              <div className="w-0 flex-1 flex items-center">
                <p className="ml-3 font-medium text-white text-wrap">
                  <span className="inline">
                    By using this website, you agree to our{' '}
                    <Link css={[tw`underline`, tw`text-white`]} to="/cookies">
                      cookie policy
                    </Link>
                    .
                  </span>
                </p>
              </div>
              <div className="order-2 flex-shrink-0 sm:order-3 sm:ml-2">
                <button
                  type="button"
                  className="-mr-1 flex p-2 rounded-md hover:bg-blue-500 focus:outline-none focus:bg-blue-500 transition ease-in-out duration-150"
                  aria-label="Dismiss"
                  onClick={() => {
                    setCookie(cookieName, true, {
                      maxAge: 60 * 60 * 24 * 31 /* 1 month */,
                    })
                  }}
                >
                  <svg
                    className="h-6 w-6 text-white"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M6 18L18 6M6 6l12 12"
                    />
                  </svg>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    )
  }
}

export default CookieBanner
