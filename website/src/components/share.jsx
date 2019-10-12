/** @jsx jsx */
import { jsx } from "theme-ui";

import { useStaticQuery, graphql } from "gatsby";
import Facebook from "../../assets/facebook.svg";
import Twitter from "../../assets/twitter.svg";
import Mail from "../../assets/mail.svg";

const shareUrl = (title, tags, url, dst) => {
  if (dst === "facebook") {
    return `https://www.facebook.com/sharer.php?u=${url}`;
  } else if (dst === "twitter") {
    return `https://twitter.com/intent/tweet?url=${url}&text=${title}&hashtags=${tags}`;
  } else if (dst === "mail") {
    return `mailto:?subject=${title}&body=${url}`;
  }
};

export default ({ path, title, tags }) => {
  const {
    site: {
      siteMetadata: { siteUrl }
    }
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
          siteUrl
        }
      }
    }
  `);
  const url = `${siteUrl}/${path}`;
  return (
    <div
      sx={{
        display: "flex",
        flexDirection: "row",
        alignItems: "center",
        justifyContent: "center",
        my: 4
      }}
    >
      <a
        href={shareUrl(title, tags, url, "twitter")}
        alt="Share the blog post on Twitter"
      >
        <Twitter sx={{ width: [40, 50], height: [40, 50], mx: 3 }} />
      </a>
      <a
        href={shareUrl(title, tags, url, "facebook")}
        alt="Share the blog post on Facebook"
      >
        <Facebook sx={{ width: [40, 50], height: [25, 40], mx: 3 }} />
      </a>
      <a
        href={shareUrl(title, tags, url, "mail")}
        alt="Share the blog post via email"
      >
        <Mail sx={{ width: [40, 50], height: [40, 50], mx: 3 }} />
      </a>
    </div>
  );
};
