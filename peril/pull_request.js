import { schedule, danger, warn, fail } from 'danger'
import { includes } from 'lodash'

// Ensure that the tuistenv binary is generated when tuistenv files are modified
const hasTuistEnvBin = includes(danger.git.modified_files, 'bin/tuistenv')
const tuistEnvFiles = danger.git.modified_files.filter(path => {
  return path.includes('Sources/TuistEnvKit')
})

if (tuistEnvFiles.length > 0 && !hasTuistEnvBin) {
  fail(
    "bin/tuistenv needs to be regenerated. Run 'make build-env' and commit the changes."
  )
}
