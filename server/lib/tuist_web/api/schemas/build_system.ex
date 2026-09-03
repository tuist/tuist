defmodule TuistWeb.API.Schemas.BuildSystem do
  @moduledoc false

  alias OpenApiSpex.Schema

  def schema do
    %Schema{
      type: :string,
      description: "The build system used by the test run.",
      enum: ["xcode", "gradle"],
      default: "xcode"
    }
  end
end
