defmodule TuistWeb.API.Schemas.Shards.Shard do
  @moduledoc false
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Tests.TestImpact.SkippedTest

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "Shard",
    type: :object,
    description: "A shard with its assigned modules, suites, and download URLs.",
    properties: %{
      shard_plan_id: %Schema{
        type: :string,
        format: :uuid,
        description: "The UUID of the shard plan."
      },
      modules: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "The test modules assigned to this shard."
      },
      suites: %Schema{
        type: :object,
        additionalProperties: %Schema{
          type: :array,
          items: %Schema{type: :string}
        },
        description: "The test suites assigned to this shard, grouped by module name."
      },
      skip: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description:
          "Test identifiers this shard must skip (`-skip-testing`). Set on the final suite catch-all shard, which runs everything not explicitly assigned to earlier shards so newly added or un-enumerated suites are not dropped. Empty for regular shards."
      },
      test_impact_skip: %Schema{
        type: :array,
        items: SkippedTest,
        description:
          "For plans created with a `test_impact_run_id`: the tests in this shard's suites that coverage-based test selection skipped. The final catch-all shard's list also has the other shards' suites and everything selection skipped outside them. Absent for other plans."
      },
      download_url: %Schema{
        type: :string,
        description:
          "Presigned URL to download the legacy single test products bundle. Present only for plans uploaded as one bundle; omitted when per-shard artifacts are used."
      },
      download_urls: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description:
          "Presigned URLs to download the products this shard needs: the shared artifact plus one per assigned module (or the single legacy bundle)."
      }
    },
    required: [:shard_plan_id, :modules, :suites, :download_urls]
  })
end
