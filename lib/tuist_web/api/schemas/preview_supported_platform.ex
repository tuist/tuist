defmodule TuistWeb.API.Schemas.PreviewSupportedPlatform do
  @moduledoc """
  The schema for the preview supported platform.
  """
  require OpenApiSpex
  alias Tuist.Previews.Preview

  OpenApiSpex.schema(%{
    type: :string,
    enum: Ecto.Enum.values(Preview, :supported_platforms)
  })
end
