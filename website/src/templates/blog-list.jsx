/** @jsx jsx */
import { jsx, Styled } from "theme-ui";

import Layout from "../components/layout";
import Meta from "../components/meta";
import TitledHeader from "../components/titled-header";
import Footer from "../components/footer";
import { Link } from "gatsby";
import { graphql } from "gatsby";
import Main from "../components/main";

const Post = ({ post }) => {
  return (
    <article sx={{ mt: 5 }}>
      <header>
        <Styled.h2 sx={{ mb: 2 }}>
          <Link to={post.fields.slug}>{post.frontmatter.title}</Link>
        </Styled.h2>
      </header>
      <p sx={{ mb: 0, color: "accent", fontSize: 2 }}>
        Published on {post.fields.date} by {post.frontmatter.author}
      </p>
      <p sx={{ my: 3 }}>{post.frontmatter.excerpt}</p>
      <p>
        <Link sx={{ color: "primaryComplementary" }} to={post.fields.slug}>
          Read on
        </Link>
      </p>
    </article>
  );
};

const PostsFooter = ({ currentPage, numPages }) => {
  const isFirst = currentPage === 1;
  const isLast = currentPage === numPages;
  const prevPage =
    currentPage - 1 === 1 ? "/blog/" : `/blog/${(currentPage - 1).toString()}`;
  const nextPage = `/blog/${(currentPage + 1).toString()}`;

  return (
    <div
      sx={{
        display: "flex",
        flex: 1,
        flexDirection: "row",
        justifyContent: "space-between"
      }}
    >
      {!isFirst && <Link to={prevPage}>Previous page</Link>}
      {!isLast && <Link to={nextPage}>Next page</Link>}
    </div>
  );
};

const BlogList = ({
  pageContext,
  data: {
    allMdx: { edges }
  }
}) => {
  const description =
    "The blog for Tuist, your best friend to use Xcode at scale.";
  return (
    <Layout>
      <Meta title="Blog" description={description} />
      <TitledHeader title="Blog" description={description} />
      <Main>
        {edges.map(({ node }, index) => {
          return <Post post={node} key={index} />;
        })}
        <PostsFooter {...pageContext} />
      </Main>
      <Footer />
    </Layout>
  );
};

export default BlogList;

export const blogListQuery = graphql`
  query blogListQuery($skip: Int!, $limit: Int!) {
    allMdx(
      filter: { fields: { type: { eq: "blog-post" } } }
      sort: { order: DESC, fields: [fields___date] }
      limit: $limit
      skip: $skip
    ) {
      edges {
        node {
          id
          fields {
            date
            slug
          }
          frontmatter {
            categories
            title
            excerpt
            author
          }
        }
      }
    }
  }
`;
