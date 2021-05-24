import React from 'react'
import Head from 'next/head'
import Footer from '../components/Footer'

type Props = {
  children?: React.ReactElement
}

const MainLayout = ({ children }: Props) => {
  return (
    <div className="container">
      <Head>
        <link
          rel="preload"
          href="/fonts/ModernEra-ExtraBold.otf"
          as="font"
          crossOrigin=""
        />
        <link
          rel="preload"
          href="/fonts/ModernEra-Regular.otf"
          as="font"
          crossOrigin=""
        />
        <link
          rel="preload"
          href="/fonts/ModernEraMono-Bold.otf"
          as="font"
          crossOrigin=""
        />
      </Head>
      <main>{children}</main>
      <Footer />
    </div>
  )
}

export default MainLayout
