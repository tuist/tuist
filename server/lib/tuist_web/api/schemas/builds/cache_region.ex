defmodule TuistWeb.API.Schemas.Builds.CacheRegion do
  @moduledoc """
  Where a build came from and which remote cache region served it.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "BuildCacheRegion",
    type: :object,
    nullable: true,
    description:
      "Where the build came from and which remote cache region served it. A mismatch between the serving and " <>
        "expected regions usually means a VPN or DNS resolver routes the machine to a far region. Null when the " <>
        "build recorded none of this.",
    properties: %{
      client_origin: %Schema{
        type: :string,
        nullable: true,
        description:
          "Where the build was uploaded from: an ISO 3166-1 country code, narrowed to an ISO 3166-2 subdivision " <>
            "in countries with more than one cache region."
      },
      expected_region: %Schema{
        type: :string,
        nullable: true,
        description: "The account's cache region nearest to the client origin."
      },
      serving_region: %Schema{
        type: :string,
        nullable: true,
        description: "The cache region that answered most of the build's remote cache requests."
      },
      serving_node: %Schema{
        type: :string,
        nullable: true,
        description: "The cache node in the serving region that answered most of them."
      },
      serving_region_share: %Schema{
        type: :number,
        nullable: true,
        description: "Share of the build's recorded remote cache requests the serving region answered, from 0 to 1."
      },
      connected_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description:
          "When the connection that served the build was established, which is also when its host was resolved."
      },
      connected_before_build_seconds: %Schema{
        type: :integer,
        nullable: true,
        description: "How long that connection had been open when the build started. 0 when it opened during the build."
      },
      verdict: %Schema{
        type: :string,
        enum: ["match", "mismatch", "unknown"],
        description:
          "Whether the serving region is the expected one. Unknown when either is missing, or when a private " <>
            "runner cache served the build."
      }
    },
    required: [:verdict]
  })
end
