import React from 'react'
import tw from 'twin.macro'
import useSiteLinks from '../hooks/useSiteLinks'

const Footer = () => {
  const links = useSiteLinks()
  console.log(links)
  return (
    <footer css={[tw`bg-pink-200`]}>
      <div css={[tw`max-w-6xl mx-auto bg-green-200`]}>
        <div>Get started</div>
        <div>Manifest specification</div>
        <div>Dependencies</div>
        <div>Contributors</div>
        <div>Slack</div>
        <div>GitHub</div>
        <div>Blog</div>
        <div>Releases</div>
      </div>
    </footer>
  )
}
export default Footer
