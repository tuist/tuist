import React from 'react'
import tw from 'twin.macro'
import useSiteLinks from '../hooks/useSiteLinks'
import { Link } from 'gatsby'

const Header = () => {
  const siteLinks = useSiteLinks()
  const linkCSS = [
    tw`p-2 hover:bg-purple-100 hover:rounded-md hover:text-purple-700`,
  ]

  return (
    <header css={[tw`py-6 px-8 flex flex-row items-center space-x-3`]}>
      <div css={[tw`bg-purple-100`]}>Logo</div>
      <nav css={[tw`flex flex-row flex-1 items-center space-x-3`]}>
        <Link css={linkCSS} to="/">
          Get started
        </Link>
        <Link css={linkCSS} to="/">
          Documentation
        </Link>
        <Link css={linkCSS} to="/">
          About
        </Link>
        <a css={linkCSS} href={siteLinks.githubOrganization} target="__blank">
          GitHub
        </a>
        <a css={[tw`flex-1`]} />
        <div>Curious? Join our</div>
        <a
          css={[tw`bg-gray-100 font-bold p-2 rounded-md hover:bg-gray-200`]}
          href={siteLinks.slack}
          target="__blank"
        >
          Tuist Slack channel
        </a>
      </nav>
    </header>
  )
}

export default Header
