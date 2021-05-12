import React from 'react'
import { Redirect, useLocation } from '@docusaurus/router'
import config from '../../../docusaurus.config'

function Home() {
  const location = useLocation()
  const defaultUrl = [
    location.pathname.replace(/\/$/, ''),
    'tutorial/get-started',
  ].join('/')

  return <Redirect to={defaultUrl} />
}

export default Home
