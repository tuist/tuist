/** @jsx jsx */
import { jsx, Styled } from "theme-ui";

import { graphql, useStaticQuery } from "gatsby";
import { MDXRenderer } from "gatsby-plugin-mdx";
import Layout from "../components/layout";
import Meta from "../components/meta";
import TitledHeader from "../components/titled-header";
import Footer from "../components/footer";
import Main from "../components/main";

const Examples = () => {
  let {
    allMdx: { edges: examples }
  } = useStaticQuery(graphql`
    {
      allMdx(
        filter: { fileAbsolutePath: { glob: "**/markdown/examples/**" } }
      ) {
        edges {
          node {
            frontmatter {
              title
            }
            body
          }
        }
      }
    }
  `);
  examples = examples.map(example => example.node);
  const description =
    "This page contains examples of different Xcode project setups defined with Tuist";
  return (
    <Layout>
      <Meta title="Examples" description={description} />
      <TitledHeader title="Examples" description={description} />
      <Main>
        <div sx={{ py: 4 }}>
          <p>
            This page contains examples of project configurations defined with
            Tuist
          </p>
          {examples.map((example, index) => {
            return (
              <div key={index}>
                <Styled.h2 sx={{ marginTop: 5 }}>
                  {example.frontmatter.title}
                </Styled.h2>
                <MDXRenderer>{example.body}</MDXRenderer>
              </div>
            );
          })}
        </div>
      </Main>
      <Footer />
    </Layout>
  );
};

export default Examples;
