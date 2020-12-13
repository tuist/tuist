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
      mdx(fileAbsolutePath: { glob: "**/cookies.mdx" }) {
        body
      }
    }
  `)
  return (
    <OldLayout>
      <SEO title="Cookie Policy" />
      <GatsbySeo
        title="Cookie Policy"
        description={`We use cookies to help improve your experience of Tuist. This cookie policy is part of Tuist' privacy policy, and covers the use of cookies between your device and our site. We also provide basic information on third-party services we may use, who may also use cookies as part of their service, though they are not covered by our policy.`}
      />
      <Main>
        <Styled.h1>Cookie Policy</Styled.h1>
        <MDXRenderer>{markdownBody}</MDXRenderer>
      </Main>
    </OldLayout>
  )
}
