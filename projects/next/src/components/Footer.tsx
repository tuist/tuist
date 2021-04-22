/** @jsx jsx */
import { jsx } from 'theme-ui'
import React from 'react'
import useSiteLinks from '../hooks/useSiteLinks'
import logo from '../images/logo.svg'
import blogIcon from './images/blog_icon.svg'

const Footer = () => {
  const links = useSiteLinks()
  return (
    <footer
      sx={{
        bg: 'green',
        display: 'flex',
        flexDirection: 'row',
        justifyContent: 'center',
        py: 5,
      }}
    >
      <div sx={{ bg: 'red' }}>Yolo</div>
    </footer>
  )
}
export default Footer
