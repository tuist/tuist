/** @jsx jsx */
import { jsx } from 'theme-ui'
import React from 'react'
import { GatsbySeo } from 'gatsby-plugin-next-seo'
import Footer from '../components/Footer'
import Header from '../components/Header'
import '../styles/global.css'

type MainLayoutProps = {
  children?: React.ReactElement
}

const MainLayout = ({ children, ...rest }: MainLayoutProps) => (
  <main {...rest}>
    <GatsbySeo titleTemplate="%s" />
    <Header />
    {children}
    <Footer />
  </main>
)

export default MainLayout
