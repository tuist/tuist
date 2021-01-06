export type GitHubData = {
  contributors: number
  stars: number
  forks: number
}

const useGitHubData = (): GitHubData => {
  return {
    contributors: 44,
    stars: 33,
    forks: 1,
  }
}

export default useGitHubData
