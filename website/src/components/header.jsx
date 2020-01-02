/** @jsx jsx */
import { jsx } from 'theme-ui'
import { withPrefix, Link, useStaticQuery, graphql } from 'gatsby'
import { Styled } from 'theme-ui'
import { Location } from '@reach/router'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faGithub } from '@fortawesome/free-brands-svg-icons'
import { faSlack } from '@fortawesome/free-brands-svg-icons'

export default () => {
  const hoverStyle = {
    color: 'primary',
  }
  const focusStyle = {
    marginTop: '3px',
    borderBottom: '3px solid',
    borderBottomColor: theme => theme.colors.primary,
  }
  const linkStyle = {
    '&:hover': hoverStyle,
    '&:focus-visible': focusStyle,
  }
  const {
    site: {
      siteMetadata: { githubUrl, slackUrl, firstDocumentationPagePath },
    },
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
          githubUrl
          slackUrl
          firstDocumentationPagePath
        }
      }
    }
  `)
  return (
    <header>
      <nav
        sx={{
          display: 'flex',
          flexDirection: ['column', 'column', 'row'],
          py: 3,
          px: 6,
        }}
      >
        <Link
          to="/"
          sx={{
            flex: 1,
            display: 'flex',
            flexDirection: 'row',
            justifyContent: ['center', 'center', 'flex-start'],
            alignItems: 'center',
          }}
        >
          <img
            src={withPrefix('logo.svg')}
            sx={{ height: 30, width: 30 }}
            alt="Tuist's logotype"
          />
          <Styled.h2 sx={{ color: 'gray1', ml: 2, my: 0 }}>Tuist</Styled.h2>
        </Link>
        <Location>
          {({ location }) => {
            const isDocs = location.pathname.startsWith('/docs')
            const isBlog = location.pathname.startsWith('/blog')
            const isFaq = location.pathname.startsWith('/faq')
            return (
              <div
                sx={{
                  display: 'flex',
                  flexDirection: ['column', 'column', 'row'],
                  flex: 1,
                  justifyContent: ['center', 'center', 'flex-end'],
                  alignItems: 'center',
                }}
              >
                <Link
                  sx={{
                    ...linkStyle,
                    ...(isDocs ? hoverStyle : {}),
                    my: [2, 0, 0],
                  }}
                  to={firstDocumentationPagePath}
                >
                  DOCS
                </Link>
                <Link
                  sx={{
                    ...linkStyle,
                    ...(isBlog ? hoverStyle : {}),
                    my: [2, 0, 0],
                    ml: [0, 0, 4],
                  }}
                  to="/blog"
                  alt="Blog"
                >
                  BLOG
                </Link>
                <Link
                  sx={{
                    ...linkStyle,
                    ...(isFaq ? hoverStyle : {}),
                    my: [2, 0, 0],
                    ml: [0, 0, 4],
                  }}
                  to="/faq"
                  alt="Frequently asked questions"
                >
                  FAQ
                </Link>
                <a
                  sx={{
                    ...linkStyle,
                    my: [2, 0, 0],
                    ml: [0, 0, 4],
                    display: 'flex',
                    flexDirection: 'row',
                    alignItems: 'center',
                  }}
                  target="__blank"
                  href={githubUrl}
                  alt="The project's GitHub organization"
                >
                  <span>GITHUB</span>
                  <FontAwesomeIcon
                    sx={{ ml: 2, mt: -1 }}
                    icon={faGithub}
                    size="sm"
                  />
                </a>
                <a
                  sx={{
                    ...linkStyle,
                    my: [2, 0, 0],
                    ml: [0, 0, 4],
                    display: 'flex',
                    flexDirection: 'row',
                    alignItems: 'center',
                  }}
                  target="__blank"
                  href={slackUrl}
                  alt="Join the organization's Slack channel"
                >
                  <span>SLACK</span>
                  <FontAwesomeIcon
                    sx={{ ml: 2, mt: -1 }}
                    icon={faSlack}
                    size="sm"
                  />
                </a>
              </div>
            )
          }}
        </Location>
      </nav>
    </header>
  )
}
