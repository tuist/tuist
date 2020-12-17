import React from 'react'
import { GlobalStyles } from 'twin.macro'

type LayoutProps = {
  children?: React.ReactChild | React.ReactChild[]
}

const Layout = ({ children, ...rest }: LayoutProps): JSX.Element => (
  <div {...rest}>
    <GlobalStyles />
    {children}
  </div>
)

export default Layout
