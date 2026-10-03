defmodule Atlas.Documents.Paperless do
  @moduledoc """
  Imports documents from a Paperless-ngx instance through its REST API.

  Lists documents from `GET /api/documents/` and streams each file from
  `GET /api/documents/{id}/download/` into `Atlas.Documents.create_from_path/3`,
  tagging the source as "paperless" and recording the Paperless id in
  `attributes` so re-runs skip already-imported documents.

  This is designed to run inside the cluster (for example via `bin/atlas eval`)
  so it can reach both Paperless and the Atlas database and object storage. It
  only needs the Paperless base URL and an API token, read from `:atlas,
  :paperless` config or passed as options. Paperless authenticates with an
  `Authorization: Token <token>` header.

  API reference: https://docs.paperless-ngx.com/api/
  """

  alias Atlas.Documents

  require Logger

  @page_size 100
  @receive_timeout :timer.seconds(60)

  @doc """
  Imports documents from Paperless.

  Options:

    * `:limit` - maximum number of documents to import (default: all).
    * `:base_url` / `:token` - override the configured Paperless endpoint.
    * `:enqueue?` - whether to enqueue processing for each document (default: true).

  Returns `{:ok, %{imported: n, skipped: n, failed: n}}` or
  `{:error, :paperless_not_configured}`.
  """
  def import(opts \\ []) do
    with {:ok, config} <- fetch_config(opts),
         {:ok, documents} <- list_documents(config, Keyword.get(opts, :limit)) do
      enqueue? = Keyword.get(opts, :enqueue?, true)

      Logger.info("Paperless import: processing #{length(documents)} document(s)")

      summary =
        Enum.reduce(documents, %{imported: 0, skipped: 0, failed: 0}, fn document, acc ->
          Map.update!(acc, import_one(config, document, enqueue?), &(&1 + 1))
        end)

      Logger.info("Paperless import finished: #{inspect(summary)}")
      {:ok, summary}
    end
  end

  defp import_one(config, document, enqueue?) do
    id = document["id"]

    if Documents.imported_from_paperless?(id) do
      Logger.info("Paperless ##{id} already imported, skipping")
      :skipped
    else
      store_document(config, document, enqueue?, id)
    end
  end

  defp store_document(config, document, enqueue?, id) do
    case download_and_create(config, document, enqueue?) do
      {:ok, created} ->
        Logger.info("Paperless ##{id} imported as document #{created.id}")
        :imported

      {:error, reason} ->
        Logger.error("Paperless ##{id} import failed: #{inspect(reason)}")
        :failed
    end
  end

  defp download_and_create(config, document, enqueue?) do
    id = document["id"]
    filename = document["original_file_name"] || "paperless-#{id}.pdf"

    with {:ok, %{body: body, content_type: content_type}} <- download(config, id),
         {:ok, path} <- write_temp(filename, body) do
      Documents.create_from_path(
        path,
        %{
          "title" => document["title"],
          "original_filename" => filename,
          "content_type" => content_type,
          "source" => "paperless",
          "attributes" => %{
            "paperless_id" => id,
            "paperless_created" => document["created"],
            "paperless_title" => document["title"]
          }
        },
        enqueue?: enqueue?
      )
    end
  end

  defp write_temp(filename, body) do
    with {:ok, path} <- Briefly.create(prefix: "paperless", extname: Path.extname(filename)),
         :ok <- File.write(path, body) do
      {:ok, path}
    end
  end

  # Walks the paginated listing, accumulating documents until the optional
  # limit is reached or there are no more pages. A failed page propagates as
  # {:error, reason} rather than silently halting, so a mid-pagination failure
  # cannot make a partial import look complete.
  defp list_documents(config, limit), do: collect_documents(config, 1, limit, [])

  defp collect_documents(config, page, limit, acc) do
    case fetch_page(config, page) do
      {:ok, %{"results" => results} = body} when is_list(results) ->
        acc = acc ++ results

        cond do
          is_integer(limit) and length(acc) >= limit -> {:ok, Enum.take(acc, limit)}
          body["next"] in [nil, ""] -> {:ok, acc}
          true -> collect_documents(config, page + 1, limit, acc)
        end

      {:ok, _body} ->
        {:error, {:paperless_list_failed, :unexpected_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_page(config, page) do
    case request(config, api_url(config, "/api/documents/"), params: [page: page, page_size: @page_size]) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:paperless_list_failed, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp download(config, id) do
    case request(config, api_url(config, "/api/documents/#{id}/download/")) do
      {:ok, %Req.Response{status: 200} = response} ->
        {:ok, %{body: response.body, content_type: content_type(response.headers)}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:paperless_download_failed, id, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(config, url, opts \\ []) do
    [
      url: url,
      headers: [{"authorization", "Token #{config.token}"}],
      receive_timeout: @receive_timeout
    ]
    |> Keyword.merge(opts)
    |> Req.new()
    |> Req.request()
  end

  defp api_url(config, path) do
    config.base_url |> URI.parse() |> URI.append_path(path) |> URI.to_string()
  end

  defp content_type(headers) do
    case headers["content-type"] do
      [value | _] -> value |> String.split(";") |> hd() |> String.trim()
      value when is_binary(value) -> value
      _other -> "application/octet-stream"
    end
  end

  defp fetch_config(opts) do
    config = Application.get_env(:atlas, :paperless, [])
    base_url = opts[:base_url] || config[:base_url]
    token = opts[:token] || config[:token]

    if present?(base_url) and present?(token) do
      {:ok, %{base_url: base_url, token: token}}
    else
      {:error, :paperless_not_configured}
    end
  end

  defp present?(value), do: is_binary(value) and value != ""
end
