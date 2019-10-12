//* @jsx jsx */
import { jsx } from "theme-ui";
import { useStaticQuery, graphql, Link } from "gatsby";

const Footer = () => {
  const centerStyle = { textAlign: "center" };
  const {
    site: { siteMetadata }
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
          githubUrl
          releasesUrl
          documentationUrl
          slackUrl
        }
      }
    }
  `);
  return (
    <div
      sx={{
        display: "flex",
        bg: "secondary",
        fontSize: 1,
        padding: 4,
        color: "primary",
        flexDirection: ["column", "row"]
      }}
    >
      <div
        sx={{
          textAlign: ["center", "left"],
          marginBottom: [3, 0]
        }}
      >
        Tuist is a project from{" "}
        <a href="https://twitter.com/pepibumur">Pedro Piñera</a> and the Tuist
        community
      </div>
      <div sx={{ flex: 1 }} />
      <div
        sx={{
          display: "flex",
          marginTop: [3, 0],
          flexDirection: ["column", "row"],
          justifyContent: ["center", "center"]
        }}
      >
        <div sx={{ ...centerStyle, marginRight: 2 }}>
          <a href={siteMetadata.githubUrl} target="__blank">
            GitHub
          </a>
        </div>
        <div sx={{ ...centerStyle, marginRight: 2 }}>
          <Link to="/blog">Blog</Link>
        </div>
        <div sx={{ ...centerStyle, marginRight: 2 }}>
          <a href={siteMetadata.releasesUrl} target="__blank">
            Releases
          </a>
        </div>
        <div sx={{ ...centerStyle, marginRight: 2 }}>
          <a href={siteMetadata.documentationUrl} target="__blank">
            Documentation
          </a>
        </div>
        <div sx={{ ...centerStyle, marginRight: 2 }}>
          <a href={siteMetadata.slackUrl} target="__blank">
            Slack
          </a>
        </div>
      </div>
    </div>
  );
};

export default Footer;
