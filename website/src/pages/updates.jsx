/** @jsx jsx */
import { jsx, Styled } from "theme-ui";

import { graphql, useStaticQuery } from "gatsby";
import Layout from "../components/layout";
import Meta from "../components/meta";
import TitledHeader from "../components/titled-header";
import Footer from "../components/footer";
import Main from "../components/main";
import { Timeline } from "gatsby-theme-micro-blog";

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
  const description = "This page contains tiny updates about the project";
  return (
    <Layout>
      <Meta title="Updates" description={description} />
      <TitledHeader title="Updates" description={description} />
      <Main>
        <div sx={{ py: 4 }}>
          <Timeline />
        </div>
      </Main>
      <Footer />
    </Layout>
  );
};

export default Examples;
