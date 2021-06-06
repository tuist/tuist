/** @jsx jsx */
import { jsx, MenuButton } from 'theme-ui'
import { Link, useStaticQuery, graphql } from 'gatsby'
import { Styled, useColorMode, useThemeUI } from 'theme-ui'
import { Location } from '@reach/router'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faGithub } from '@fortawesome/free-brands-svg-icons'
import { faSlack } from '@fortawesome/free-brands-svg-icons'
import logo from '../../static/logo.svg'

export default ({ menuOpen, setMenuOpen, menuRef }) => {
  const hoverStyle = {
    color: 'primary',
  }
  const focusStyle = {
    marginTop: '3px',
    borderBottom: '3px solid',
    borderBottomColor: (theme) => theme.colors.primary,
  }
  const linkStyle = {
    fontSize: 2,
    '&:hover': hoverStyle,
    '&:focus-visible': focusStyle,
  }
  const {
    site: {
      siteMetadata: { githubUrl, slackUrl, shopUrl },
    },
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
          githubUrl
          slackUrl
          shopUrl
        }
      }
    }
  `)
  const { theme } = useThemeUI()
  return (
    <header>
      <nav
        sx={{
          display: 'flex',
          flexDirection: ['column', 'row'],
          py: 3,
          px: [2, 4, 4, 6],
        }}
      >
        <div
          sx={{
            display: 'flex',
            flexDirection: 'horizontal',
            justifyContent: 'center',
          }}
        >
          {setMenuOpen && (
            <MenuButton
              size={10}
              sx={{ display: ['inherit', 'none'], zIndex: 1 }}
              onClick={(e) => {
                setMenuOpen(!menuOpen)
                if (!menuRef.current) return
                const navLink = menuRef.current.querySelector('a')
                if (navLink) navLink.focus()
              }}
            />
          )}
          {setMenuOpen && <div sx={{ flex: 1 }} />}
          <Link
            to="/"
            sx={{
              variant: 'text.header',
              flex: '0 0',
              display: 'flex',
              flexDirection: 'row',
              justifyContent: 'flex-start',
              alignItems: 'center',
            }}
          >
            <img
              src={logo}
              sx={{ height: 30, width: 30, flex: '0 0 30', minWidth: 30 }}
              alt="Tuist's logotype"
            />
            <Styled.h2 sx={{ color: 'gray1', ml: 2, my: 0, flex: 1 }}>
              Tuist
            </Styled.h2>
          </Link>
        </div>
        <Location>
          {({ location }) => {
            const isBlog = location.pathname.startsWith('/blog')
            const isAppsAtScale = location.pathname.startsWith('/apps-at-scale')
            return (
              <div
                sx={{
                  display: 'flex',
                  flexDirection: ['column', 'row'],
                  flex: 1,
                  justifyContent: ['center', 'center', 'flex-end'],
                  alignItems: 'center',
                  mt: [3, 0],
                }}
              >
                <div
                  sx={{
                    display: 'flex',
                    flexDirection: ['column', 'row'],
                    alignItems: ['center'],
                  }}
                >
                  <a
                    sx={{
                      ...linkStyle,
                      variant: 'text.header',
                    }}
                    href="https://docs.tuist.io"
                  >
                    DOCS
                  </a>
                  <Link
                    sx={{
                      ...linkStyle,
                      ...(isBlog ? hoverStyle : {}),
                      ml: [0, 4],
                      variant: 'text.header',
                    }}
                    to="/blog"
                    alt="Blog"
                  >
                    BLOG
                  </Link>
                  <Link
                    sx={{
                      ...linkStyle,
                      ...(isAppsAtScale ? hoverStyle : {}),
                      ml: [0, 4],
                      variant: 'text.header',
                    }}
                    to="/apps-at-scale"
                    alt="Interviews to developers doing app development at scale"
                  >
                    APPS AT SCALE
                  </Link>
                </div>

                <div sx={{ flexDirection: 'row', display: 'flex', mt: [3, 0] }}>
                  <a
                    sx={{
                      ...linkStyle,
                      ml: [0, 4],
                      display: 'flex',
                      flexDirection: 'row',
                      alignItems: 'center',
                    }}
                    target="__blank"
                    href={githubUrl}
                    alt="The project's GitHub organization"
                  >
                    <FontAwesomeIcon
                      sx={{
                        mt: -1,
                        path: { fill: theme.colors.text },
                        '&:hover': { path: { fill: theme.colors.primary } },
                      }}
                      icon={faGithub}
                      size="lg"
                    />
                  </a>
                  <a
                    sx={{
                      ...linkStyle,
                      ml: 4,
                      display: 'flex',
                      flexDirection: 'row',
                      alignItems: 'center',
                    }}
                    target="__blank"
                    href={slackUrl}
                    alt="Join the organization's Slack channel"
                  >
                    <FontAwesomeIcon
                      sx={{
                        mt: -1,
                        path: { fill: theme.colors.text },
                        '&:hover': { path: { fill: theme.colors.primary } },
                      }}
                      icon={faSlack}
                      size="lg"
                    />
                  </a>
                </div>
              </div>
            )
          }}
        </Location>
      </nav>
    </header>
  )
}
