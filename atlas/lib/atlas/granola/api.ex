defmodule Atlas.Granola.API do
  @moduledoc """
  Thin client for Granola's public meeting notes API.
  """

  alias Atlas.Granola.Note

  require Logger

  @default_base_url "https://public-api.granola.ai/v1"
  @default_page_size 30
  @default_receive_timeout 10_000

  @doc """
  Lists all accessible Granola notes for the provided filters.

  Returns `:disabled` when no Granola API key is configured.
  """
  def list_notes(opts \\ []) do
    client = client(opts)

    with {:ok, key} <- fetch_api_key(client) do
      opts =
        opts
        |> Keyword.take([:created_before, :created_after, :updated_after, :page_size])
        |> Keyword.put_new(:page_size, @default_page_size)

      fetch_notes(client, key, opts, [])
    end
  end

  @doc """
  Fetches a single Granola note by ID.

  Pass `include: :transcript` when transcript content is needed.
  """
  def get_note(note_id, opts \\ []) when is_binary(note_id) do
    client = client(opts)

    with {:ok, key} <- fetch_api_key(client) do
      params =
        case Keyword.get(opts, :include) do
          :transcript -> [include: "transcript"]
          "transcript" -> [include: "transcript"]
          _ -> []
        end

      request = request(client, key, "/notes/#{note_id}", params)

      case client.request.(request) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          case Note.from_api(body) do
            %Note{} = note -> {:ok, note}
            nil -> {:error, {:invalid_response, body}}
          end

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.warning("Granola get_note failed: status=#{status} body=#{inspect(body)}")
          {:error, {:http, status}}

        {:error, reason} ->
          Logger.warning("Granola get_note transport error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp fetch_notes(client, key, opts, notes) do
    params = encode_params(opts)
    request = request(client, key, "/notes", params)

    case client.request.(request) do
      {:ok, %Req.Response{status: 200, body: %{"notes" => page_notes} = body}} when is_list(page_notes) ->
        decoded_notes = Enum.map(page_notes, &Note.from_api/1) |> Enum.reject(&is_nil/1)
        notes = notes ++ decoded_notes

        if body["hasMore"] && is_binary(body["cursor"]) && body["cursor"] != "" do
          fetch_notes(client, key, Keyword.put(opts, :cursor, body["cursor"]), notes)
        else
          {:ok, notes}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Granola list_notes failed: status=#{status} body=#{inspect(body)}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("Granola list_notes transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp request(client, key, path, params) do
    Req.new(
      url: client.base_url <> path,
      auth: {:bearer, key},
      receive_timeout: client.receive_timeout,
      headers: [{"accept", "application/json"}]
    )
    |> Req.merge(params: params)
  end

  defp encode_params(opts) do
    opts
    |> Keyword.take([:created_before, :created_after, :updated_after, :cursor, :page_size])
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Enum.map(fn {key, value} -> {key, encode_param(value)} end)
  end

  defp encode_param(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp encode_param(%Date{} = date), do: Date.to_iso8601(date)
  defp encode_param(value), do: value

  defp fetch_api_key(client) do
    case client.api_key do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> :disabled
    end
  end

  defp client(opts) do
    config = granola_config()

    %{
      api_key: configured_option(opts, config, :api_key),
      base_url: base_url(configured_option(opts, config, :base_url)),
      receive_timeout: receive_timeout(configured_option(opts, config, :receive_timeout)),
      request: Keyword.get(opts, :request, &Req.get/1)
    }
  end

  defp configured_option(opts, config, key) do
    if Keyword.has_key?(opts, key), do: Keyword.get(opts, key), else: Keyword.get(config, key)
  end

  defp base_url(nil), do: @default_base_url
  defp base_url(""), do: @default_base_url
  defp base_url(value), do: String.trim_trailing(value, "/")

  defp receive_timeout(timeout) do
    case timeout do
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _ -> @default_receive_timeout
    end
  end

  defp granola_config, do: Application.get_env(:atlas, :granola, [])
end
