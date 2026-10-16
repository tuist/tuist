# Mix task entry points

Keep tasks thin: parse strict options, delegate behavior, and provide useful Mix errors.
Do not start the customer application just to perform setup or authentication.

## Project setup

`mix tuist.setup --project account/project` delegates source editing to
`TuistEx.ProjectSetup`. Install the compile bootstrap and test wrapper together.
Use ordinary Mix aliases, not SDK function captures: the SDK is not necessarily
loaded in the parent on cold parallel builds. Preserve Phoenix test preparation
and environment-dependent alias expressions; never freeze their current value.

- Preserve unrelated aliases, options, comments and file permissions.
- Refuse customized compile actions and unsupported source shapes without writing.
- Parse and format the complete update before atomically replacing a regular file.
- Never evaluate source fragments to discover what to edit.
- Test repeat setup in fresh processes, matching how users invoke Mix, without
  modifying shared environment variables or global Mix state in the test VM.
- The shared setup command belongs in the Elixir Get started guide. Feature
  guides link back; retries and CI sharding remain optional. Manual bootstrap
  and troubleshooting belong in the advanced cache guide.
