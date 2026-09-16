defmodule CacheWeb.API.ContentDigestSpec do
  @moduledoc """
  OpenAPI declarations for `tuist-checksum-sha256`, shared by every artifact
  lane that accepts and serves a client-declared digest.
  """

  def request_parameter do
    [
      in: :header,
      schema: %OpenApiSpex.Schema{type: :string},
      required: false,
      description:
        "Lowercase hex SHA-256 of the request body. When present, a body that does not match is refused with 422, " <>
          "a malformed value with 400, and the digest is served back with the artifact."
    ]
  end

  def response_header do
    %OpenApiSpex.Header{
      description:
        "Lowercase hex SHA-256 of the whole artifact, as declared by its uploader and verified at upload. " <>
          "Absent for artifacts uploaded without one.",
      schema: %OpenApiSpex.Schema{type: :string}
    }
  end
end
