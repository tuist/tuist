/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import { useStaticQuery, graphql } from 'gatsby'
import OldLayout from '../components/old-layout'
import Main from '../components/main'
import { MDXRenderer } from 'gatsby-plugin-mdx'
import { GatsbySeo } from 'gatsby-plugin-next-seo'
import SEO from '../components/SEO'

export default () => {
  const {
    mdx: { body: markdownBody },
  } = useStaticQuery(graphql`
    query {
      mdx(fileAbsolutePath: { glob: "**/privacy.mdx" }) {
        body
      }
    }
  `)
  return (
    <OldLayout>
      <SEO title="Privacy Policy" />
      <GatsbySeo
        title="Privacy Policy"
        description={`By accessing the website at tuist.io and scle.tuist.io, you are agreeing to be bound by these terms of service, all applicable laws and regulations, and agree that you are responsible for compliance with any applicable local laws. If you do not agree with any of these terms, you are prohibited from using or accessing this site. The materials contained in this website are protected by applicable copyright and trademark law.
        `}
      />
      <Main>
        <Styled.h1>Privacy Policy</Styled.h1>
        <MDXRenderer>{markdownBody}</MDXRenderer>
      </Main>
    </OldLayout>
  )
}
