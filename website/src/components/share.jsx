/** @jsx jsx */
import { jsx } from 'theme-ui'
import { FacebookIcon, TwitterIcon, EmailIcon } from 'react-share'

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
  const url = `${siteUrl}/${path}`
  return (
    <div>
      <p sx={{ textAlign: 'center', mt: 4, mb: 2, color: 'gray3' }}>
        Share ♥ the blog post with others
      </p>
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
          <TwitterIcon size={32} round={true} sx={{ mx: 3 }} />
        </a>
        <a
          sx={{ mx: 3 }}
          href={shareUrl(title, tags, url, 'facebook')}
          alt="Share the blog post on Facebook"
        >
          <FacebookIcon size={32} round={true} sx={{ mx: 3 }} />
        </a>
        <a
          sx={{ mx: 3 }}
          href={shareUrl(title, tags, url, 'mail')}
          alt="Share the blog post via email"
        >
          <EmailIcon size={32} round={true} />
        </a>
      </div>
    </div>
  )
}
