/// https://github.com/gatsbyjs/gatsby/issues/9979#issuecomment-627344993
exports.onPreRenderHTML = function onPreRenderHTML({
  getHeadComponents,
  replaceHeadComponents,
}) {
  const headComponents = getHeadComponents()
  headComponents.sort((a, b) => {
    if (a.type === b.type || (a.type !== 'style' && b.type !== 'style')) {
      return 0
    }

    if (a.type === 'style') {
      return 1
    } else if (b.type === 'style') {
      return -1
    }

    return 0
  })

  replaceHeadComponents(headComponents)
}
