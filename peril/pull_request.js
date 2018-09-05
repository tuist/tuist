import { schedule, danger, warn, fail } from 'danger'
import { includes } from 'lodash'

// Variables

const modified = danger.git.modified_files
const newFiles = danger.git.created_files
const files = [danger.git.modified_files, danger.git.created_files].flat

// Utilities

const apiParams = () => ({
  ...danger.github.thisPR,
  ref: danger.github.pr.head.ref,
})

const getContent = path => {
  return await danger.github.api.repos.getContent({ ...apiParams(), path })
}

// Error handling
const checkErrorHandling = async () => {
  // do { /* some swift code */ } catch { /* some rescue logic here */ }
  const regex = /do\s*\{[\s\S]*\}\s*catch\s*{[\s\S]*\}/
  await files.forEach((path) => {
    const content = await getContent(path)
    if (regex.test(content)) {
      fail(`The file ${path} is handling errors without a concrete list`)
    }
  })
}


// Schedule

schedule(async () => {
  await checkErrorHandling()
})

