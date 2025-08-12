defmodule TuistWeb.API.Schemas.Bundle do
  @moduledoc """
  The schema for a bundle.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.BundleSupportedPlatform

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "Bundle",
    description: "Response schema for bundle",
    type: :object,
    properties: %{
      id: %Schema{
        type: :string,
        description:
          "The ID of the bundle. This is not a bundle ID that you'd set in Xcode but the database identifier of the bundle."
      },
      name: %Schema{
        type: :string,
        description: "The name of the bundle"
      },
      app_bundle_id: %Schema{
        type: :string,
        description: "The bundle ID of the app"
      },
      version: %Schema{
        type: :string,
        description: "The version of the bundle"
      },
      supported_platforms: %Schema{
        type: :array,
        description: "List of supported platforms",
        items: BundleSupportedPlatform
      },
      install_size: %Schema{
        type: :integer,
        description: "The bundle install size in bytes"
      },
      download_size: %Schema{
        type: :integer,
        description: "The bundle download size in bytes"
      },
      git_branch: %Schema{
        type: :string,
        description: "The git branch associated with the bundle."
      },
      git_commit_sha: %Schema{
        type: :string,
        description: "The git commit SHA associated with the bundle."
      },
      git_ref: %Schema{
        type: :string,
        description:
          "Git reference of the repository. When run from CI in a pull request, this will be the remote reference to the pull request, such as `refs/pull/23958/merge`."
      },
      inserted_at: %Schema{
        type: :string,
        format: "date-time",
        description: "When the bundle was created"
      },
      uploaded_by_account: %Schema{
        type: :string,
        description: "The account that uploaded this bundle"
      },
      artifacts: %Schema{
        type: :array,
        description: "The artifacts in this bundle",
        items: TuistWeb.API.Schemas.BundleArtifact
      },
      url: %Schema{
        type: :string,
        description: "The URL to view this bundle"
      }
    },
    required: [
      :id,
      :name,
      :app_bundle_id,
      :version,
      :supported_platforms,
      :install_size,
      :inserted_at,
      :uploaded_by_account,
      :url
    ]
  })
end
