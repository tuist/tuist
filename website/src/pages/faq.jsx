/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import { useStaticQuery, graphql } from 'gatsby'
import Layout from '../components/layout'
import Main from '../components/main'
import { MDXRenderer } from 'gatsby-plugin-mdx'
import { FAQJsonLd, GatsbySeo } from 'gatsby-plugin-next-seo'
import Footer from '../components/footer'
import SEO from '../components/SEO'

const Question = ({ question, body, index }) => {
  return (
    <article key={index}>
      <header>
        <Styled.h2>{question}</Styled.h2>
      </header>
      <main>
        <MDXRenderer>{body}</MDXRenderer>
      </main>
    </article>
  )
}

export default () => {
  const {
    allMdx: { nodes: questions },
  } = useStaticQuery(graphql`
    {
      allMdx(filter: { fileAbsolutePath: { regex: "/faq/.*/" } }) {
        nodes {
          frontmatter {
            question
          }
          excerpt(pruneLength: 5000)
          body
        }
      }
    }
  `)
  const structuredQuestions = questions.map(question => {
    return { question: question.frontmatter.question, answer: question.excerpt }
  })
  return (
    <Layout>
      <SEO />
      <FAQJsonLd questions={structuredQuestions} />
      <GatsbySeo
        title="FAQ"
        description={`This page contains answers for questions that are frequently asked by users. Questions such as "Should I gitignore my project?" or "How does Tuist compare to the Swift Package Manager?"`}
      />
      <Main>
        <Styled.h1>Frequently asked questions</Styled.h1>
        {questions.map((question, index) => {
          return (
            <Question
              question={question.frontmatter.question}
              body={question.body}
              key={index}
            />
          )
        })}
      </Main>
      <Footer />
    </Layout>
  )
}
