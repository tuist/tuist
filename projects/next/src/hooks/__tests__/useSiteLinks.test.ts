import useSiteLinks from '../useSiteLinks'
import { useStaticQuery, graphql } from 'gatsby'
const mockUseStaticQuery = useStaticQuery as jest.Mock<any>
const mockGraphql = graphql as jest.Mock

const graphqlQuery = `
query SiteLinks {
  site {
    siteMetadata {
      links {
        slack
        releases
        githubRepository
        githubOrganization
      }
    }
  }
}
`

describe('useSiteLinks', () => {
  it('returns the Slack link from the site metadata', () => {
    // Given
    const slackUrl = 'https://slack.tuist.io'
    mockUseStaticQuery.mockReturnValue({
      site: {
        siteMetadata: {
          links: {
            slack: slackUrl,
          },
        },
      },
    })

    // When
    const got = useSiteLinks()

    // Then
    expect(mockGraphql).toMatchSnapshot()
    expect(got.slack).toBe(slackUrl)
  })

  it('returns the releases link from the site metadata', () => {
    // Given
    const releasesUrl = 'https://github.com/tuist/tuist/releases'
    mockUseStaticQuery.mockReturnValue({
      site: {
        siteMetadata: {
          links: {
            releases: releasesUrl,
          },
        },
      },
    })

    // When
    const got = useSiteLinks()

    // Then
    expect(mockGraphql).toMatchSnapshot()
    expect(got.releases).toBe(releasesUrl)
  })

  it('returns the GitHub repository link from the site metadata', () => {
    // Given
    const githubUrl = 'https://github.com/tuist/tuist'
    mockUseStaticQuery.mockReturnValue({
      site: {
        siteMetadata: {
          links: {
            githubRepository: githubUrl,
          },
        },
      },
    })

    // When
    const got = useSiteLinks()

    // Then
    expect(mockGraphql).toMatchSnapshot()
    expect(got.githubRepository).toBe(githubUrl)
  })

  it('returns the GitHub organization link from the site metadata', () => {
    // Given
    const githubUrl = 'https://github.com/tuist'
    mockUseStaticQuery.mockReturnValue({
      site: {
        siteMetadata: {
          links: {
            githubOrganization: githubUrl,
          },
        },
      },
    })

    // When
    const got = useSiteLinks()

    // Then
    expect(mockGraphql).toMatchSnapshot()
    expect(got.githubOrganization).toBe(githubUrl)
  })
})
