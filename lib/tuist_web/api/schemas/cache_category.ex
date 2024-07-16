defmodule TuistWeb.API.Schemas.CacheCategory do
  @moduledoc """
  The schema for the cache category.
  """

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CacheCategory",
    description: "The category of the cache.",
    type: :string,
    enum: ["tests", "builds"],
    default: "builds"
  })
end
