export type GitHubData = {
  name: string
}

const useGitHubData = (): GitHubData => {
  return {
    name: 'test',
  }
}

export default useGitHubData
