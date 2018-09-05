import { schedule, danger, warn, fail, message } from 'danger'
import { flatten } from 'lodash'

// Variables

const allChangedFiles = [
  ...danger.git.modified_files,
  ...danger.git.created_files,
]

// Utilities

const apiParams = () => ({
  ...danger.github.thisPR,
  ref: danger.github.pr.head.ref,
})

const getContent = async path => {
  const content = await danger.github.api.repos.getContent({
    ...apiParams(),
    path,
  })
  return content
}

// Error handling
const checkErrorHandling = async () => {
  // do { /* some swift code */ } catch { /* some rescue logic here */ }
  const regex = /do\s*\{[\s\S]*\}\s*catch\s*{[\s\S]*\}/
  await allChangedFiles.forEach(async path => {
    const content = await getContent(path)
    message(content)
    if (regex.test(content)) {
      fail(`The file ${path} is handling errors without a concrete list`)
    }
  })
}

// Schedule

schedule(checkErrorHandling())
