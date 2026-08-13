defmodule Tuist.MCP.ArtifactDownload do
  @moduledoc """
  Presigns a stored artifact for an MCP tool response.

  Tools hand back a temporary URL rather than the bytes: a result bundle or a
  build archive can run to gigabytes, which no JSON-RPC response should carry.
  The object is sized first, so a tool can tell the difference between an
  artifact that is there and one whose row outlived it — a run whose bundle was
  never uploaded, or has since been pruned, is the common case when someone is
  looking into a failure days later.

  One hour matches the window `list_test_case_run_attachments` already hands out.
  """

  alias Tuist.Storage

  @expires_in 3600

  @doc """
  Returns `{:ok, artifact}` for a stored object, `{:error, :not_stored}` when
  storage has no object under `object_key`, or `{:error, reason}` when storage
  could not be reached.
  """
  def presign(object_key, account) do
    case Storage.get_object_size(object_key, account) do
      {:ok, byte_size} ->
        {:ok,
         %{
           object_key: object_key,
           byte_size: byte_size,
           download_url:
             Storage.generate_download_url(object_key, account,
               expires_in: @expires_in,
               content_disposition: ~s(attachment; filename="#{Path.basename(object_key)}")
             ),
           expires_at: DateTime.utc_now() |> DateTime.add(@expires_in, :second) |> DateTime.truncate(:second)
         }}

      {:error, :not_found} ->
        {:error, :not_stored}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Same as `presign/2`, but reports a missing object as `{:ok, nil}` so a tool can
  describe several artifacts of one record in a single response. A storage
  failure still surfaces as an error rather than an absent artifact — during an
  outage "we could not look" must not read as "it was never uploaded".
  """
  def presign_optional(object_key, account) do
    case presign(object_key, account) do
      {:ok, artifact} -> {:ok, artifact}
      {:error, :not_stored} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The JSON schema fragment describing a presigned artifact."
  def schema(nullable \\ false) do
    %{
      "type" => if(nullable, do: ["object", "null"], else: "object"),
      "properties" => %{
        "object_key" => %{"type" => "string"},
        "byte_size" => %{"type" => "integer"},
        "download_url" => %{"type" => "string"},
        "expires_at" => %{"type" => "string"}
      },
      "required" => ["object_key", "byte_size", "download_url", "expires_at"],
      "additionalProperties" => false
    }
  end
end
