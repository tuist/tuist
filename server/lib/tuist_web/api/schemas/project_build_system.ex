defmodule TuistWeb.API.Schemas.ProjectBuildSystem do
  @moduledoc false

  alias OpenApiSpex.Schema

  def schema do
    %Schema{
      type: :string,
      description: "The build system used by the project.",
      enum: ["xcode", "gradle", "bazel"],
      default: "xcode"
    }
  end
end
