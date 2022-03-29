/** @jsx jsx */
import { jsx, Styled, useThemeUI } from 'theme-ui'
import { useStaticQuery, graphql, Link } from 'gatsby'
import { faGithub, faTwitter } from '@fortawesome/free-brands-svg-icons'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'

export default () => {
  const { theme } = useThemeUI()

  const {
    site: {
      siteMetadata: { githubUrl, slackUrl, releasesUrl, twitterUrl },
    },
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
          twitterUrl
          githubUrl
          slackUrl
          releasesUrl
        }
      }
    }
  `)
  return (
    <footer>
      <div sx={{ bg: 'background' }}>
        <div className="max-w-screen-xl mx-auto py-12 px-4 overflow-hidden sm:px-6 lg:px-8">
          <nav className="-mx-5 -my-2 flex flex-wrap justify-center">
            <div className="px-5 py-2">
              <Link
                to="/blog"
                className="text-base leading-6"
                sx={{ color: 'gray', ':hover': { color: 'primary' } }}
              >
                Blog
              </Link>
            </div>
            <div className="px-5 py-2">
              <Link
                alt="Opens the project documentation/"
                to="https://docs.tuist.io"
                className="text-base leading-6"
                sx={{ color: 'gray', ':hover': { color: 'primary' } }}
              >
                Documentation
              </Link>
            </div>
            <div className="px-5 py-2">
              <a
                href={releasesUrl}
                alt="Opens the releases page."
                target="__blank"
                className="text-base leading-6"
                sx={{ color: 'gray', ':hover': { color: 'primary' } }}
              >
                Releases
              </a>
            </div>
          </nav>
          <div className="mt-8 flex justify-center">
            <a
              href={twitterUrl}
              target="__blank"
              alt="Opens the Twitter account of Tuist"
              className="ml-6 text-gray-400 hover:text-gray-500"
            >
              <span className="sr-only">Twitter</span>
              <FontAwesomeIcon
                sx={{
                  mt: -1,
                  path: { fill: theme.colors.gray },
                  '&:hover': { path: { fill: theme.colors.primary } },
                }}
                icon={faTwitter}
                size="lg"
              />
            </a>
            <a
              href={githubUrl}
              target="__blank"
              alt="Opens the Tuist organization on GitHub"
              className="ml-6 text-gray-400 hover:text-gray-500"
            >
              <span className="sr-only">GitHub</span>
              <FontAwesomeIcon
                sx={{
                  mt: -1,
                  path: { fill: theme.colors.gray },
                  '&:hover': { path: { fill: theme.colors.primary } },
                }}
                icon={faGithub}
                size="lg"
              />
            </a>
          </div>
          <div className="mt-8">
            <p
              className="text-center text-base leading-6"
              sx={{ color: 'gray' }}
            >
              Tuist © Copyright 2022. All rights reserved.
            </p>
          </div>
        </div>
      </div>
    </footer>
  )
}
