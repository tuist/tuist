/** @jsx jsx */
import { jsx, useThemeUI } from 'theme-ui'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faFacebook, faTwitter } from '@fortawesome/free-brands-svg-icons'
import { faEnvelope } from '@fortawesome/free-regular-svg-icons'

import { useStaticQuery, graphql } from 'gatsby'

const shareUrl = (title, tags, url, dst) => {
  if (dst === 'facebook') {
    return `https://www.facebook.com/sharer.php?u=${url}`
  } else if (dst === 'twitter') {
    return `https://twitter.com/intent/tweet?url=${url}&text=${title}&hashtags=${tags}`
  } else if (dst === 'mail') {
    return `mailto:?subject=${title}&body=${url}`
  }
}

export default ({ path, title, tags }) => {
  const {
    site: {
      siteMetadata: { siteUrl },
    },
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
          siteUrl
        }
      }
    }
  `)
  const { theme } = useThemeUI()
  const url = `${siteUrl}/${path}`
  return (
    <div sx={{ mt: 4 }}>
      <div
        sx={{
          display: 'flex',
          flexDirection: 'row',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <a
          href={shareUrl(title, tags, url, 'twitter')}
          alt="Share the blog post on Twitter"
        >
          <FontAwesomeIcon
            sx={{
              mx: 3,
              path: { fill: theme.colors.text },
              '&:hover': { path: { fill: theme.colors.primary } },
            }}
            icon={faTwitter}
            size="lg"
          />
        </a>
        <a
          sx={{ mx: 3 }}
          href={shareUrl(title, tags, url, 'facebook')}
          alt="Share the blog post on Facebook"
        >
          <FontAwesomeIcon
            sx={{
              mx: 3,
              path: { fill: theme.colors.text },
              '&:hover': { path: { fill: theme.colors.primary } },
            }}
            icon={faFacebook}
            size="lg"
          />
        </a>
        <a
          sx={{ mx: 3 }}
          href={shareUrl(title, tags, url, 'mail')}
          alt="Share the blog post via email"
        >
          <FontAwesomeIcon
            sx={{
              mx: 3,
              path: { fill: theme.colors.text },
              '&:hover': { path: { fill: theme.colors.primary } },
            }}
            icon={faEnvelope}
            size="lg"
          />
        </a>
      </div>
    </div>
  )
}
