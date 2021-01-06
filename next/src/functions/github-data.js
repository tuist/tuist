const fetch = require('node-fetch').default

exports.handler = async function (event, context) {
  const url = `https://api.github.com/repos/tuist/tuist/stats/participation`
  const response = await fetch(url, {
    method: 'GET',
    cache: 'no-cache',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/vnd.github.v3+json',
      Authorization: `token ${process.env.GITHUB_TOKEN}`,
    },
  })
  const body = response.json()
  return {
    statusCode: 200,
    body: JSON.stringify(body),
  }
}
