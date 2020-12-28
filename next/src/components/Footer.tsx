import React from 'react'
import tw from 'twin.macro'
import useSiteLinks from '../hooks/useSiteLinks'
import logo from '../images/logo.svg'

const Footer = () => {
  const links = useSiteLinks()
  const css = [tw`hover:text-primary focus:text-primary focus:underline`]
  return (
    <footer css={[tw`font-tuist flex flex-col items-center py-20`]}>
      <div
        css={[
          tw`mx-10 md:mx-auto md:max-w-2xl flex flex-col items-center space-y-6`,
        ]}
      >
        <div css={[tw`flex flex-row space-x-2 items-center`]}>
          <img src={logo} alt="Tuist's logo" css={[tw`w-8 h-8`]} />
          <div css={[tw`text-2xl font-normal`]}>tuist</div>
        </div>
        <div
          css={[tw`flex flex-row flex-wrap space-x-3 justify-center text-lg`]}
        >
          <a target="__blank" css={css}>
            Get started
          </a>
          <a target="__blank" css={css}>
            Manifest specification
          </a>
          <a target="__blank" css={css}>
            Dependencies
          </a>
          <a target="__blank" css={css}>
            Contributors
          </a>
          <a href={links.slack} target="__blank" css={css}>
            Slack
          </a>
          <a href={links.githubOrganization} target="__blank" css={css}>
            GitHub
          </a>
          <a target="__blank" css={css}>
            Blog
          </a>
          <a href={links.releases} target="__blank" css={css}>
            Releases
          </a>
        </div>
      </div>
    </footer>
  )
}
export default Footer
