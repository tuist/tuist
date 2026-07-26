defmodule Tuist.Registry.Swift.Metadata do
  @moduledoc """
  Server-side read/write helpers for Swift package registry metadata.

  The shared metadata contract lives in `TuistCommon.Registry.Swift.Metadata`;
  this module only owns the server runtime's object-storage calls.
  """

  alias Tuist.Registry.S3
  alias TuistCommon.Registry.Swift.Metadata, as: MetadataContract

  def get_package(scope, name, _opts \\ []) do
    key = MetadataContract.s3_key(scope, name)

    case S3.get_object(key) do
      {:ok, body} ->
        case MetadataContract.decode_package(body) do
          {:ok, metadata} -> {:ok, metadata}
          {:error, _reason} -> {:error, :not_found}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:s3_error, reason}}
    end
  end

  def put_package(scope, name, metadata) do
    key = MetadataContract.s3_key(scope, name)
    body = MetadataContract.encode_package!(metadata)

    S3.upload_content(key, body, content_type: "application/json")
  end
end
