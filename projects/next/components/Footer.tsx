/** @jsxImportSource theme-ui */
import React from 'react'
import Image from 'next/image'

const FooterLink = ({
  href,
  children,
}: {
  href: string
  children?: React.ReactNode
}) => {
  return (
    <a href={href} target="_blank" sx={{ mx: 2 }}>
      {children}
    </a>
  )
}

const Footer = () => {
  return (
    <footer
      sx={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        width: '100%',
        background: 'red',
      }}
    >
      <div
        sx={{
          display: 'flex',
          flex: 'row',
          alignItems: 'center',
          fontSize: 4,
        }}
      >
        <Image
          src="/images/logo.svg"
          alt="Tuist's logo"
          width={36}
          height={36}
        />
        <div sx={{ ml: 2 }}>Tuist</div>
      </div>
      <div>
        <FooterLink href="https://docs.tuist.io/tutorial/get-started">
          Get started
        </FooterLink>
        <FooterLink href="https://docs.tuist.io/manifests/project/">
          Manifest reference
        </FooterLink>
        <FooterLink href="https://github.com/tuist/tuist/graphs/contributors">
          Contributors
        </FooterLink>
        <FooterLink href="https://github.com/tuist/tuist/releases">
          Releases
        </FooterLink>
      </div>
    </footer>
  )
}

export default Footer
