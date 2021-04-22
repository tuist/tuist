import React from 'react'
import { GatsbySeo } from 'gatsby-plugin-next-seo'
import Footer from '../components/Footer'
import Header from '../components/Header'

type MainLayoutProps = {
  children: React.ReactChildren | React.ReactChildren[]
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
