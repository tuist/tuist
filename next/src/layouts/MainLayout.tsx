import React from 'react'
import { GlobalStyles } from 'twin.macro'
import { GatsbySeo } from 'gatsby-plugin-next-seo'

type MainLayoutProps = {
  children: React.ReactChildren | React.ReactChildren[]
}

const MainLayout = ({ children, ...rest }: MainLayoutProps) => (
  <main {...rest}>
    <GlobalStyles />
    <GatsbySeo titleTemplate="%s" />
    {children}
  </main>
)

export default MainLayout
