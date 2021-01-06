const fetch = require('node-fetch').default

exports.handler = async function (event, context) {
  const url = `https://api.github.com/repos/tuist/tuist/stats/participation`
  const headers = {
    'Content-Type': 'application/json',
    Accept: 'application/vnd.github.v3+json',
    Authorization: `token ${process.env.GITHUB_TOKEN}`,
  }
  const response = await fetch(url, { headers })
  const body = await response.json()
  return {
    statusCode: 200,
    body: JSON.stringify(body),
  }
}
