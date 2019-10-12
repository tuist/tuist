/** @jsx jsx */
import { jsx } from "theme-ui";
import { MDXRenderer } from "gatsby-plugin-mdx";

import Layout from "../components/layout";
import Meta from "../components/meta";
import TitledHeader from "../components/titled-header";
import Footer from "../components/footer";
import { graphql } from "gatsby";
import moment from "moment";
import Main from "../components/main";
import EditPage from "../components/edit-page";
import Share from "../components/share";

const Avatar = ({ author: { avatar, twitter } }) => {
  return (
    <a href={`https://twitter.com/${twitter}`} target="__blank">
      <img
        sx={{
          my: [20, 0],
          width: [90, 140],
          height: [90, 140],
          borderRadius: [45, 70]
        }}
        src={avatar}
      />
    </a>
  );
};

const IndexPage = ({
  data: {
    mdx,
    allAuthorsYaml: { edges }
  }
}) => {
  const post = mdx;
  const authors = edges.map(edge => edge.node);
  const author = authors.find(
    author => author.handle === post.frontmatter.author
  );
  const subtitle = `Published by ${author.name} on ${moment(
    post.fields.date
  ).format("MMMM Do YYYY")}`;
  return (
    <Layout>
      <Meta
        title={post.frontmatter.title}
        description={post.frontmatter.excerpt}
        keywords={post.frontmatter.categories}
        author={author.twitter}
        slug={post.fields.slug}
      />
      <TitledHeader title={post.frontmatter.title} subtitle={subtitle}>
        <Avatar author={author} />
      </TitledHeader>
      <Main>
        <div sx={{ py: 4 }}>
          <MDXRenderer>{post.body}</MDXRenderer>
        </div>
        <p>
          <EditPage path={post.fields.path} />
        </p>
        <Share
          path={post.fields.slug}
          tags={post.frontmatter.categories}
          title={post.frontmatter.title}
        />
      </Main>
      <Footer />
    </Layout>
  );
};

export default IndexPage;

export const query = graphql`
  query($slug: String!) {
    site {
      siteMetadata {
        title
        siteUrl
      }
    }
    mdx(fields: { slug: { eq: $slug } }) {
      body
      fields {
        slug
        date
        path
      }
      frontmatter {
        title
        categories
        excerpt
        author
      }
    }
    allAuthorsYaml {
      edges {
        node {
          name
          avatar
          twitter
          handle
        }
      }
    }
  }
`;
