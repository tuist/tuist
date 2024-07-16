defmodule TuistWeb.API.Schemas.ArtifactMultipartUploadCompletion do
  @moduledoc """
  The schema for a multipart upload completion.
  """

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ArtifactMultipartUploadCompletion",
    description: "This response confirms that the upload has been completed successfully.",
    type: :object,
    properties: %{
      status: %OpenApiSpex.Schema{type: :string, default: "success", enum: ["success"]},
      data: %OpenApiSpex.Schema{
        type: :object,
        properties: %{}
      }
    }
  })
end
