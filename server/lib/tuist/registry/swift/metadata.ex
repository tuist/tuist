defmodule Tuist.Registry.Swift.Metadata do
  @moduledoc """
  Server-side read/write helpers for Swift package registry metadata.

  The shared metadata contract lives in `TuistCommon.Registry.Swift.Metadata`;
  this module only owns the server runtime's object-storage calls.
  """

  alias Tuist.Registry
  alias Tuist.Registry.S3
  alias TuistCommon.Registry.Swift.Metadata, as: MetadataContract

  @skip_classification_version 2

  def verified_skip?(%{"classification_version" => @skip_classification_version}), do: true
  def verified_skip?(_skip), do: false

  def verified_skip(reason) when is_binary(reason) do
    %{
      "classification_version" => @skip_classification_version,
      "reason" => reason
    }
  end

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

  @doc """
  Re-apply a pure metadata amendment against the exact object version replaced.
  Leases reduce contention; this conditional write fences expired owners.
  """
  def update_package(scope, name, initial, amend, attempts \\ 5) do
    key = MetadataContract.s3_key(scope, name)

    with {:ok, current, condition} <- read_version(key, initial),
         {:ok, updated} <- amend.(current) do
      case S3.upload_content(
             key,
             MetadataContract.encode_package!(updated),
             [content_type: "application/json"] ++ condition
           ) do
        {:error, {:http_error, 412, _}} when attempts > 1 -> update_package(scope, name, initial, amend, attempts - 1)
        result -> result
      end
    end
  end

  defp read_version(key, initial) do
    case Registry.registry_bucket() |> ExAws.S3.get_object(key) |> S3.request() do
      {:ok, %{body: body, headers: headers}} ->
        with {:ok, metadata} <- MetadataContract.decode_package(body),
             etag when is_binary(etag) <- S3.etag_from_headers(headers) do
          {:ok, metadata, [if_match: "\"#{etag}\""]}
        else
          _ -> {:error, :invalid_metadata_version}
        end

      {:error, {:http_error, 404, _}} ->
        {:ok, initial, [if_none_match: "*"]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def put_package(scope, name, metadata) do
    key = MetadataContract.s3_key(scope, name)
    body = MetadataContract.encode_package!(metadata)

    S3.upload_content(key, body, content_type: "application/json")
  end
end
