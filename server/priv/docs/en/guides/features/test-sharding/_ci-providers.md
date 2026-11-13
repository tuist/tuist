Tuist automatically detects the following CI providers:

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

For other providers, refer to the `.tuist-shard-matrix.json` file to set up parallel jobs. On [Appcircle](#appcircle), set the shard reference explicitly and start one build per shard as shown below.
