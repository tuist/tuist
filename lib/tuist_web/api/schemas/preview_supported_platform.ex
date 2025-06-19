defmodule TuistWeb.API.Schemas.PreviewSupportedPlatform do
  @moduledoc """
  The schema for the preview supported platform.
  """
  alias Tuist.AppBuilds.AppBuild

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :string,
    enum: Ecto.Enum.values(AppBuild, :supported_platforms)
  })
end
