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
      mdx(fileAbsolutePath: { glob: "**/terms.mdx" }) {
        body
      }
    }
  `)
  return (
    <OldLayout>
      <SEO title="Terms of Service" />
      <GatsbySeo
        title="Terms of Service"
        description={`This page contains answers for questions that are frequently asked by users. Questions such as "Should I gitignore my project?" or "How does Tuist compare to the Swift Package Manager?"`}
      />
      <Main>
        <Styled.h1>Terms of Service</Styled.h1>
        <MDXRenderer>{markdownBody}</MDXRenderer>
      </Main>
    </OldLayout>
  )
}
