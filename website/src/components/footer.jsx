/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import { withPrefix, useStaticQuery, graphql, Link } from 'gatsby'
import Margin from './margin'

export default () => {
  const {
    site: {
      siteMetadata: { githubUrl, slackUrl, releasesUrl },
    },
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
          githubUrl
          slackUrl
          releasesUrl
        }
      }
    }
  `)
  const copyrightMessage =
    'Tuist © Copyright 2019. All rights reserved. Crafted with ♥ by Pedro Piñera & the contributors.'
  const linkStyle = {
    textDecoration: 'none',
    fontSize: 2,
    color: 'primary',
    "&:hover": {
      color: 'secondary'
    }
  }
  return (
    <footer sx={{ py: 3, bg: 'muted', flex: 1 }}>
      <Margin>
        <div
          sx={{
            display: 'flex',
            alignItems: 'center',
            flexDirection: 'column',
            flex: 1,
          }}
        >
          <div
            sx={{
              display: 'flex',
              justifyContent: 'space-between',
              flexDirection: ['column', 'row'],
              flex: 1,
              alignSelf: 'stretch',
            }}
          >
            <div
              sx={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
              }}
            >
              <div
                sx={{
                  display: 'flex',
                  flexDirection: 'row',
                  alignItems: 'center',
                }}
              >
                <img
                  src={withPrefix('logo.svg')}
                  sx={{ height: 30, width: 30 }}
                  alt="Tuist's logotype"
                />
                <Styled.h2 sx={{ color: 'text', ml: 2, my: 0 }}>
                  Tuist
                </Styled.h2>
              </div>
            </div>
            <div
              sx={{
                mt: [3, 0],
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
              }}
            >
              <Styled.h2 sx={{ color: 'text', mb: 9, mt: 0 }}>
                Documentation
              </Styled.h2>
              <Link to="/docs/usage/getting-started/" sx={linkStyle}>
                Getting started
              </Link>
              <Link to="/docs/usage/projectswift/" sx={linkStyle}>
                Manifest specification
              </Link>
              <Link to="/docs/usage/dependencies/" sx={linkStyle}>
                Dependencies
              </Link>
              <Link to="/docs/contribution/tuist/" sx={linkStyle}>
                Contributors
              </Link>
              <div
                sx={{
                  fontSize: 1,
                  mt: 3,
                  display: ['none', 'block'],
                  color: 'gray',
                  textAlign: 'center'
                }}
              >
                {copyrightMessage}
              </div>
            </div>
            <div
              sx={{
                mt: [3, 0],
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
              }}
            >
              <Styled.h2 sx={{ color: 'text', mb: 9, mt: [3, 0] }}>
                Other
              </Styled.h2>
              <a
                sx={linkStyle}
                target="__blank"
                href={githubUrl}
                alt="Opens the Tuist's organizqtion on GitHub"
              >
                GitHub
              </a>
              <a
                sx={linkStyle}
                target="__blank"
                href={slackUrl}
                alt="Join the Slack group"
              >
                Slack
              </a>
              <Link to="/blog" sx={linkStyle}>
                Blog
              </Link>
              <a
                sx={linkStyle}
                target="__blank"
                href={releasesUrl}
                alt="Check out the releases on GitHub"
              >
                Releases
              </a>
            </div>
            <div
              sx={{
                fontSize: 1,
                mt: 3,
                display: ['block', 'none'],
                textAlign: 'center',
                color: 'gray'
              }}
            >
              {copyrightMessage}
            </div>
          </div>
        </div>
      </Margin>
    </footer>
  )
}
