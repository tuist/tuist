defmodule TuistWeb.API.Schemas.BundleSupportedPlatform do
  @moduledoc """
  The schema for the bundle supported platform.
  """
  alias Tuist.Bundles.Bundle

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "BundleSupportedPlatform",
    description: "A platform that a bundle can support (e.g. iOS)",
    type: :string,
    enum: Ecto.Enum.values(Bundle, :supported_platforms)
  })
end
