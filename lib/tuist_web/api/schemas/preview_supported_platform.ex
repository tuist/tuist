defmodule TuistWeb.API.Schemas.PreviewSupportedPlatform do
  @moduledoc """
  The schema for the preview supported platform.
  """
  alias Tuist.Previews.Preview

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :string,
    enum: Ecto.Enum.values(Preview, :supported_platforms)
  })
end
