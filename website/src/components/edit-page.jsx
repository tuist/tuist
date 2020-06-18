/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import React from 'react'
import { useStaticQuery, graphql } from 'gatsby'

export default ({ path }) => {
  const {
    site: {
      siteMetadata: { editUrl },
    },
  } = useStaticQuery(graphql`
    query {
      site {
        siteMetadata {
          editUrl
        }
      }
    }
  `)
  const url = `${editUrl}/markdown/${path}`
  return (
    <Styled.a
      href={url}
      sx={{ textAlign: 'center' }}
      target="__blank"
      alt="Open GitHub to edit the content of the current page"
    >
      This page can be edited on GitHub
    </Styled.a>
  )
}
