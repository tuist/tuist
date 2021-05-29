import React from 'react'
import { Redirect, useLocation } from '@docusaurus/router'

function Home() {
  const location = useLocation()
  const defaultUrl = [
    location.pathname.replace(/\/$/, ''),
    'tutorial/get-started',
  ].join('/')

  return <Redirect to={defaultUrl} />
}

export default Home
