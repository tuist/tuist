import React from "react";
import Helmet from "react-helmet";
import { useStaticQuery, graphql } from "gatsby";

function Meta({ description, lang, meta, keywords, title, author, slug }) {
  const { site } = useStaticQuery(
    graphql`
      query {
        site {
          siteMetadata {
            siteUrl
            title
            description
          }
        }
      }
    `
  );

  const metaDescription = description || site.siteMetadata.description;
  const metaTitle = title || site.siteMetadata.title;
  const titleTemplate = title ? `%s | ${site.siteMetadata.title}` : `%s`;
  return (
    <Helmet
      htmlAttributes={{
        lang
      }}
      title={metaTitle}
      titleTemplate={titleTemplate}
      meta={[
        {
          name: `description`,
          content: metaDescription
        },
        {
          property: `og:title`,
          content: title
        },
        {
          property: `og:description`,
          content: metaDescription
        },
        {
          property: `og:type`,
          content: `website`
        },
        {
          name: `twitter:card`,
          content: `summary`
        },
        {
          name: `twitter:creator`,
          content: site.siteMetadata.author
        },
        {
          name: `twitter:title`,
          content: title
        },
        {
          name: `twitter:description`,
          content: metaDescription
        }
      ]
        .concat(
          keywords.length > 0
            ? {
                name: `keywords`,
                content: keywords.join(`, `)
              }
            : []
        )
        .concat(meta)}
    >
      <meta name="twitter:card" content="summary_large_image" />
      {slug && (
        <meta
          name="twitter:image"
          content={`${site.siteMetadata.siteUrl}${slug}twitter-card.jpg`}
        />
      )}
    </Helmet>
  );
}

Meta.defaultProps = {
  lang: `en`,
  meta: [],
  keywords: [`tuist`, `engineering`, `xcode`, `swift`]
};

export default Meta;
