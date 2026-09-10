defmodule Tuist.Sandboxes.Anthropic.ControlPlane do
  @moduledoc """
  Client for the Managed Agents control plane (`/v1/agents`,
  `/v1/sessions`), authenticated with the organization API key stored on
  an agent environment. The work queue, which authenticates with the
  environment key instead, lives in `Tuist.Sandboxes.Anthropic.Client`.

  Non-2xx answers become `{:error, %{status: status, message: message}}`
  with the message taken from the body's `error.message`.
  """

  alias Tuist.Environment

  @anthropic_version "2023-06-01"
  @anthropic_beta "managed-agents-2026-04-01"
  @default_tools [%{type: "agent_toolset_20260401"}]
  @default_events_limit 1000

  def create_agent(api_key, attrs) when is_map(attrs) do
    body =
      put_present(
        %{
          name: Map.fetch!(attrs, :name),
          model: Map.fetch!(attrs, :model),
          tools: Map.get(attrs, :tools, @default_tools)
        },
        :system,
        Map.get(attrs, :system)
      )

    api_key
    |> request()
    |> Req.post(url: "/v1/agents", json: body)
    |> handle_response()
  end

  @doc """
  Creates a session. `attrs` takes `agent`, `environment_id`, and
  optionally `title`, `metadata` (a string map), `initial_events` and
  `budget_cents`, which becomes a USD list-cost limit.
  """
  def create_session(api_key, attrs) when is_map(attrs) do
    body =
      %{agent: Map.fetch!(attrs, :agent), environment_id: Map.fetch!(attrs, :environment_id)}
      |> put_present(:title, Map.get(attrs, :title))
      |> put_present(:metadata, Map.get(attrs, :metadata))
      |> put_present(:initial_events, Map.get(attrs, :initial_events))
      |> put_budget(Map.get(attrs, :budget_cents))

    api_key
    |> request()
    |> Req.post(url: "/v1/sessions", json: body)
    |> handle_response()
  end

  def get_session(api_key, session_id) do
    api_key
    |> request()
    |> Req.get(url: session_path(session_id))
    |> handle_response()
  end

  @doc """
  Lists the session's events, oldest first unless `order: "desc"`.
  Returns the `data` list of a single page (`:limit`, default 1000).
  """
  def list_events(api_key, session_id, opts \\ []) do
    params = put_param([limit: Keyword.get(opts, :limit, @default_events_limit)], :order, Keyword.get(opts, :order))

    api_key
    |> request()
    |> Req.get(url: session_path(session_id, "events"), params: params)
    |> handle_response()
    |> case do
      {:ok, %{"data" => events}} when is_list(events) -> {:ok, events}
      {:ok, _body} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  def send_message(api_key, session_id, text) when is_binary(text) do
    api_key
    |> request()
    |> Req.post(url: session_path(session_id, "events"), json: %{events: [user_message(text)]})
    |> handle_response()
  end

  def archive_session(api_key, session_id) do
    api_key
    |> request()
    |> Req.post(url: session_path(session_id, "archive"), json: %{})
    |> handle_response()
  end

  def user_message(text) when is_binary(text) do
    %{type: "user.message", content: [%{type: "text", text: text}]}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299, do: {:ok, body}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, %{status: status, message: error_message(body)}}
  end

  defp handle_response({:error, reason}), do: {:error, reason}

  defp error_message(%{"error" => %{"message" => message}}) when is_binary(message), do: message
  defp error_message(body) when is_binary(body), do: String.slice(body, 0, 500)
  defp error_message(body), do: inspect(body)

  defp put_present(body, _key, nil), do: body
  defp put_present(body, key, value), do: Map.put(body, key, value)

  defp put_param(params, _key, nil), do: params
  defp put_param(params, key, value), do: Keyword.put(params, key, value)

  defp put_budget(body, nil), do: body

  defp put_budget(body, cents) when is_integer(cents) and cents > 0 do
    Map.put(body, :budget, %{type: "limit", max_list_cost: %{amount: Integer.to_string(cents), currency: "USD"}})
  end

  defp request(api_key) do
    Req.new(
      base_url: Environment.anthropic_api_url(),
      headers: [
        {"x-api-key", api_key},
        {"anthropic-version", @anthropic_version},
        {"anthropic-beta", @anthropic_beta}
      ],
      retry: false
    )
  end

  defp session_path(session_id), do: "/v1/sessions/#{encode(session_id)}"
  defp session_path(session_id, suffix), do: session_path(session_id) <> "/" <> suffix

  defp encode(segment), do: URI.encode(to_string(segment), &URI.char_unreserved?/1)
end
