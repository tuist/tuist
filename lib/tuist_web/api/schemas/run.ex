defmodule TuistWeb.API.Schemas.Run do
  @moduledoc """
  The schema for the run response.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    type: :object,
    description: "The schema for a Tuist run.",
    required: [
      :id,
      :name,
      :duration,
      :subcommand,
      :command_arguments,
      :tuist_version,
      :swift_version,
      :macos_version,
      :status,
      :git_commit_sha,
      :git_ref,
      :git_branch,
      :url
    ],
    properties: %{
      id: %Schema{
        type: :number,
        description: "ID of the run"
      },
      name: %Schema{
        type: :string,
        description: "Command name of the run"
      },
      duration: %Schema{
        type: :number,
        description: "Duration of the run"
      },
      subcommand: %Schema{
        type: :string,
        description: "Subcommand of the run"
      },
      command_arguments: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "Arguments passed to the command"
      },
      tuist_version: %Schema{
        type: :string,
        description: "Version of Tuist used"
      },
      swift_version: %Schema{
        type: :string,
        description: "Version of Swift used"
      },
      macos_version: %Schema{
        type: :string,
        description: "Version of macOS used"
      },
      status: %Schema{
        type: :string,
        description: "Status of the command event"
      },
      git_commit_sha: %Schema{
        type: :string,
        description: "Git commit SHA of the repository"
      },
      git_ref: %Schema{
        type: :string,
        description:
          "Git reference of the repository. When run from CI in a pull request, this will be the remote reference to the pull request, such as `refs/pull/23958/merge`."
      },
      git_branch: %Schema{
        type: :string,
        description: "Git branch of the repository"
      },
      cacheable_targets: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "Cacheable targets of the run"
      },
      local_cache_target_hits: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "Local cache target hits of the run"
      },
      remote_cache_target_hits: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "Remote cache target hits of the run"
      },
      test_targets: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "Test targets of the run"
      },
      local_test_target_hits: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "Local test target hits of the run"
      },
      remote_test_target_hits: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "Remote test target hits of the run"
      },
      preview_id: %Schema{
        type: :string,
        description: "ID of the associated preview"
      },
      url: %Schema{
        type: :string,
        description: "URL to the run"
      }
    }
  })
end
