defmodule Atlas.Documents.Storage.Local do
  @moduledoc false

  alias AtlasWeb.Endpoint

  @upload_salt "document-local-upload"

  def bucket, do: "local-documents"

  def put_object(key, body, _opts \\ []) when is_binary(key) and is_binary(body) do
    path = path_for_key(key)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, body) do
      {:ok, %{bucket: bucket(), key: key}}
    end
  end

  def get_object(key, _opts \\ []) when is_binary(key) do
    with {:ok, body} <- File.read(path_for_key(key)) do
      {:ok, %{body: body, content_type: nil, key: key}}
    end
  end

  def head_object(key, _opts \\ []) when is_binary(key) do
    case File.stat(path_for_key(key)) do
      {:ok, %File.Stat{size: size}} ->
        {:ok, %{status: 200, headers: [{"content-length", Integer.to_string(size)}]}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete_object(key, _opts \\ []) when is_binary(key) do
    case File.rm(path_for_key(key)) do
      :ok -> {:ok, %{key: key}}
      {:error, :enoent} -> {:ok, %{key: key}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Signs a local upload URL served by `AtlasWeb.DocumentUploadController`. The
  signed token carries the storage key and, when given, the required
  `Content-Type` header, so tampered uploads are refused.
  """
  def presigned_put_url(key, opts \\ []) when is_binary(key) do
    expires_in = Keyword.get(opts, :expires_in, 3600)
    content_type = Keyword.get(opts, :content_type)

    token =
      Phoenix.Token.sign(Endpoint, @upload_salt, %{
        "key" => key,
        "content_type" => content_type,
        "max_age" => expires_in
      })

    url =
      Endpoint.url()
      |> URI.new!()
      |> URI.append_path("/api/documents/uploads/local/#{token}")
      |> URI.to_string()

    {:ok, url}
  end

  def verify_upload_token(token) when is_binary(token) do
    with {:ok, %{"key" => key, "content_type" => content_type, "max_age" => max_age}} <-
           Phoenix.Token.verify(Endpoint, @upload_salt, token, max_age: max_age(token)) do
      {:ok, %{key: key, content_type: content_type, max_age: max_age}}
    end
  end

  def verify_upload_token(_token), do: {:error, :missing}

  # A signed token carries its own max_age so callers do not have to remember
  # it. Peek at the payload without verifying age to get it, then rely on
  # Phoenix.Token.verify to enforce it below.
  defp max_age(token) do
    case Phoenix.Token.verify(Endpoint, @upload_salt, token, max_age: :infinity) do
      {:ok, %{"max_age" => max_age}} when is_integer(max_age) and max_age > 0 -> max_age
      _other -> 3600
    end
  end

  defp path_for_key(key) do
    storage_dir =
      :atlas
      |> Application.get_env(:documents, [])
      |> Keyword.get(:local_storage_path, "tmp/documents")

    key
    |> String.split("/", trim: true)
    |> Enum.reduce(Path.expand(storage_dir), &Path.join(&2, &1))
  end
end
