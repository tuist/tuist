/** @jsx jsx */
import { jsx } from 'theme-ui'

import React from 'react'
import { useStaticQuery, Link, graphql } from 'gatsby'
import { slide as BurgerMenu } from 'react-burger-menu'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faSlack } from '@fortawesome/free-brands-svg-icons'
import theme from '../gatsby-plugin-theme-ui/index'
import { useColorMode } from 'theme-ui'
import ToggleButton from './toggle-button'

import {
  faBox,
  faPencilAlt,
  faBook,
  faFileCode,
  faSatellite,
  faMobile,
  faPaperPlane,
} from '@fortawesome/free-solid-svg-icons'

const styles = ({ primaryColor, textColor }) => {
  return {
    bmBurgerButton: {
      position: 'absolute',
      width: '25px',
      height: '20px',
      left: '36px',
      top: '36px',
    },
    bmBurgerBars: {
      background: 'white',
    },
    bmBurgerBarsHover: {
      background: '#a90000',
    },
    bmCrossButton: {
      height: '24px',
      width: '24px',
    },
    bmCross: {
      background: 'white',
    },
    bmMenuWrap: {
      position: 'fixed',
      height: '100%',
    },
    bmMenu: {
      background: primaryColor,
      padding: '2.5em 1.5em 0',
      fontSize: '1.15em',
    },
    bmMorphShape: {
      fill: '#373a47',
    },
    bmItemList: {
      color: textColor,
      padding: '0.8em',
    },
    bmItem: {
      display: 'block',
      outline: 'none',
      border: 0,
      marginBottom: '20px',
    },
    bmOverlay: {
      background: 'rgba(0, 0, 0, 0.3)',
    },
  }
}

const Menu = () => {
  const {
    site: { siteMetadata },
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
          githubUrl
          releasesUrl
          documentationUrl
          slackUrl
          spectrumUrl
        }
      }
    }
  `)
  const [colorMode] = useColorMode()
  let colors = {}
  if (!colorMode || colorMode == 'light') {
    colors = theme.colors
  } else {
    colors = theme.colors.modes[colorMode]
  }
  const sx = {
    display: 'flex',
    flexDirection: 'row',
    alignItems: 'center',
    '&:hover': {
      textDecoration: 'none',
    },
  }
  return (
    <BurgerMenu
      styles={styles({
        primaryColor: colors.primary,
        textColor: colors.primaryComplementary,
      })}
      noOverlay
      disableAutoFocusw
    >
      <Link to="/">
        <div sx={sx}>
          <div sx={{ width: 20 }}>
            <FontAwesomeIcon icon={faMobile} />
          </div>
          <span sx={{ marginLeft: 3 }}>Home</span>
        </div>
      </Link>

      <Link to="/examples">
        <div sx={sx}>
          <div sx={{ width: 20 }}>
            <FontAwesomeIcon icon={faFileCode} />
          </div>
          <span sx={{ marginLeft: 3 }}>Examples</span>
        </div>
      </Link>

      <a href={siteMetadata.documentationUrl} target="__blank" sx={sx}>
        <div sx={sx}>
          <div sx={{ width: 20 }}>
            <FontAwesomeIcon icon={faBook} />
          </div>
          <span sx={{ marginLeft: 3 }}>Docs</span>
        </div>
      </a>

      <Link to="/blog">
        <div sx={sx}>
          <div sx={{ width: 20 }}>
            <FontAwesomeIcon icon={faPencilAlt} />
          </div>
          <span sx={{ marginLeft: 3 }}>Blog</span>
        </div>
      </Link>

      <a href={siteMetadata.releasesUrl} target="__blank" sx={sx}>
        <div sx={sx}>
          <div sx={{ width: 20 }}>
            <FontAwesomeIcon icon={faBox} />
          </div>
          <span sx={{ marginLeft: 3 }}>Releases</span>
        </div>
      </a>

      <a href={siteMetadata.slackUrl} target="__blank" sx={sx}>
        <div sx={sx}>
          <div sx={{ width: 20 }}>
            <FontAwesomeIcon icon={faSlack} />
          </div>
          <span sx={{ marginLeft: 3 }}>Slack</span>
        </div>
      </a>

      <div sx={{ visibility: ['visible', 'visible', 'hidden'] }}>
        <ToggleButton />
      </div>
    </BurgerMenu>
  )
}
export default Menu
