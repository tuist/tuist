# App Builds

## Responsibilities
- Create previews and app builds, and link builds to previews. Uploads are
  independent of project build system. `has_previews?/1` uses a project-scoped
  existence query for sidebar discovery, without loading history or caching a
  negative result that could hide the first upload on another replica.
- Find latest previews by bundle identifier/branch/track and supported platforms.
- List previews with pagination and distinct bundle identifiers. `list_preview_tracks/1` independently returns the project's total preview count and nonempty tracks with counts, grouped case-insensitively with deterministic spelling and ordering. Count only listable previews (nonempty bundle identifiers); include untracked builds in the total. Counts ignore active search, track filters, and pagination. Literal, case-insensitive search across display names and full release notes applies before distinct selection and pagination without changing exact-name filtering. A string searches one literal substring; a list of terms requires every term to match either field, preserving the web list's word-search behavior.
- Previews can carry optional plain-text `release_notes` (up to 10,000 characters). Notes are metadata, never part of preview identity: old and new clients must group the same build even when only one supplies notes. The first nonblank notes are retained; filling a reused preview uses an atomic `release_notes IS NULL` update so competing replicas cannot overwrite them. Omitted, null, empty, and whitespace-only notes never clear stored notes. Notes follow the preview's existing retention and export rules.
- Apply supported-platform filters before choosing distinct bundle identifiers, so a newer device-only upload cannot hide an older simulator build.
