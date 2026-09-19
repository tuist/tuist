# Contract templates

The `.docx` templates that Atlas fills in to generate MSAs, DPAs, DAAs,
SLAs, and order forms are intentionally kept out of this repository. They
contain drafting decisions and boilerplate that we treat as sensitive.

At runtime they live in the private `atlas-object-storage` bucket (see
`infra/helm/atlas/values.yaml`). Atlas fetches them from there on demand;
they are not shipped in the container image.

Follow-up: `Atlas.Contracts.Template` currently reads templates from this
directory via `File.read!/1`. Swap that for a `Tuist.Storage`-style S3
fetch so this directory can stay empty. Until then, template-generation
paths will 404 in the open-source build; existing production deploys
continue to work because the private bucket is unchanged.
