# Contract templates

The `.docx` templates that Atlas fills in to generate MSAs, DPAs, DAAs,
SLAs, and order forms are intentionally kept out of this repository. They
contain drafting decisions and boilerplate that we treat as sensitive.

Production reads the real files from the `contracts/templates/<set>/`
prefix of the shared Atlas object storage bucket (`atlas-object-storage`).
`Atlas.Contracts.Storage` picks the source at boot from
`config :atlas, Atlas.Contracts, source: :disk | :s3`; runtime.exs flips
this to `:s3` whenever the bucket is configured (see
`infra/helm/atlas/values.yaml`).

The placeholder `.docx` stubs checked in beside this README are what the
disk source serves in dev and test, and what the manifest logic
enumerates in production to decide which filenames a set contains. To
change or add a template in production, replace the bucket object with
`mix atlas.contracts.upload_templates <local_dir>` (see the task's
docstring); the stubs stay untouched.
