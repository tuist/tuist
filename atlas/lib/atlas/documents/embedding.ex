defmodule Atlas.Documents.Embedding do
  @moduledoc """
  Generates text embeddings through an OpenAI-compatible `/embeddings` endpoint.

  Request and response shapes follow the OpenAI Embeddings API
  (https://platform.openai.com/docs/api-reference/embeddings); compatible
  providers expose the same contract, so the provider is selected purely by
  base URL and model.
  """

  alias Atlas.LLMs.LocalTransport

  @default_model "text-embedding-3-small"
  @max_input_terms 200
  @max_input_characters 1_000
  @fallback_input_terms 100
  @fallback_input_characters 500

  def embed(text, opts \\ []) when is_binary(text) do
    client = Keyword.get(opts, :client, configured_client())

    if client do
      client.embed(text, opts)
    else
      embed_with_req(text, opts)
    end
  end

  def configured_model do
    :atlas
    |> Application.get_env(:documents, [])
    |> Keyword.get(:embedding_model, @default_model)
  end

  defp embed_with_req(text, opts) do
    with {:ok, config} <- fetch_config(opts) do
      model = Keyword.get(opts, :model, config[:model])
      req = Keyword.get(opts, :req, &Req.request/1)

      text
      |> embedding_inputs()
      |> Enum.reduce_while(nil, fn input, _last_error ->
        config
        |> request_embedding(model, input, req)
        |> embedding_retry_step()
      end)
    end
  end

  defp request_embedding(config, model, input, req) do
    request =
      [
        method: :post,
        url: config[:base_url] |> URI.parse() |> URI.append_path("/embeddings") |> URI.to_string(),
        auth: {:bearer, config[:api_key]},
        receive_timeout: config[:receive_timeout],
        json: %{model: model, input: input}
      ]
      |> then(fn base ->
        case config[:req_http_options] do
          nil -> base
          extra when is_list(extra) -> base ++ extra
        end
      end)
      |> Req.new()

    case req.(request) do
      {:ok, %Req.Response{status: status, body: %{"data" => [%{"embedding" => embedding} | _]}}}
      when status in 200..299 and is_list(embedding) ->
        {:ok, %{model: model, embedding: embedding}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:embedding_request_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Options override configuration so callers (and tests) can supply credentials
  # and the request function without mutating global application config.
  defp fetch_config(opts) do
    documents_config = Application.get_env(:atlas, :documents, [])
    llm_config = Application.get_env(:atlas, :llm, [])

    cond do
      opts[:mode] == :local or Keyword.get(llm_config, :mode) == :local ->
        {:ok,
         %{
           # `LocalTransport` ignores the api_key, but Req requires a truthy
           # value for the `auth:` header to be set.
           api_key: "local",
           # Dummy base URL — the plug intercepts before Req touches the
           # network. Kept for URI.append_path/2 to construct a valid URL.
           base_url: "http://atlas-local",
           model: present([opts[:model], documents_config[:embedding_model], @default_model]),
           receive_timeout:
             opts[:receive_timeout] ||
               Keyword.get(documents_config, :embedding_receive_timeout, :timer.seconds(60)),
           req_http_options: opts[:req_http_options] || [plug: {LocalTransport, []}]
         }}

      api_key = present([opts[:api_key], documents_config[:embedding_api_key], llm_config[:api_key]]) ->
        {:ok,
         %{
           api_key: api_key,
           base_url:
             present([
               opts[:base_url],
               documents_config[:embedding_base_url],
               llm_config[:base_url],
               "https://api.openai.com/v1"
             ]),
           model: present([opts[:model], documents_config[:embedding_model], @default_model]),
           receive_timeout:
             opts[:receive_timeout] ||
               Keyword.get(documents_config, :embedding_receive_timeout, :timer.seconds(60))
         }}

      true ->
        {:error, :embedding_not_configured}
    end
  end

  defp present(values), do: Enum.find(values, &present?/1)

  defp present?(value), do: is_binary(value) and value != ""

  defp embedding_inputs(text) do
    [
      embedding_input(text, @max_input_terms, @max_input_characters),
      embedding_input(text, @fallback_input_terms, @fallback_input_characters)
    ]
    |> Enum.uniq()
  end

  defp embedding_input(text, max_terms, max_characters) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(max_terms)
    |> Enum.join(" ")
    |> String.slice(0, max_characters)
  end

  defp embedding_retry_step({:error, {:embedding_request_failed, _status, body}} = error) do
    if context_length_error?(body), do: {:cont, error}, else: {:halt, error}
  end

  defp embedding_retry_step(result), do: {:halt, result}

  defp context_length_error?(%{"error" => %{"message" => message}}) when is_binary(message) do
    String.contains?(message, "maximum context length")
  end

  defp context_length_error?(_body), do: false

  defp configured_client do
    :atlas
    |> Application.get_env(:documents, [])
    |> Keyword.get(:embedding_client)
  end
end
