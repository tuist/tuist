import { useStaticQuery, graphql } from 'gatsby'

type SiteLinks = {
  slack: string
  releases: string
  githubRepository: string
  githubOrganization: string
}

const useSiteLinks = (): SiteLinks => {
  const {
    site: {
      siteMetadata: {
        links: { slack, releases, githubRepository, githubOrganization },
      },
    },
  } = useStaticQuery(graphql`
    query SiteLinks {
      site {
        siteMetadata {
          links {
            slack
          }
        }
      }
    }
  `)

  return {
    slack,
    releases,
    githubRepository,
    githubOrganization,
  }
}

export default useSiteLinks
