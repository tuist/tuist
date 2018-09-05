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
  for (const path of allChangedFiles) {
    const result = await getContent(path)
    const buffer = new Buffer(result.data.content, 'base64')
    const content = buffer.toString()
    if (regex.test(content)) {
      fail(
        `The file ${path} is handling errors without passing a concrete list`
      )
    }
  }
}

// Schedule

schedule(checkErrorHandling())
