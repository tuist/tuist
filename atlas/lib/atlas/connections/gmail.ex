defmodule Atlas.Connections.Gmail do
  @moduledoc """
  On-demand, read-only Gmail access through the caller's own personal Google
  connection. Requires the separate `gmail.readonly` consent granted from
  `/settings/connections`. Tokens stay server-side; results carry message
  metadata and bounded plain-text bodies only.
  """

  alias Atlas.Audit
  alias Atlas.Connections
  alias Atlas.Users.User

  @scope "https://www.googleapis.com/auth/gmail.readonly"
  @messages "https://gmail.googleapis.com/gmail/v1/users/me/messages"
  @max_results 25
  @max_body 20_000
  @id ~r/\A[A-Za-z0-9_-]{1,100}\z/

  def scope, do: @scope

  def search(%User{} = user, query, limit \\ 10) when is_binary(query) do
    limit = limit |> max(1) |> min(@max_results)

    with {:ok, token} <- Connections.access_token(user, "google", [@scope]),
         {:ok, body} <- request(@messages, token, q: query, maxResults: limit),
         ids when is_list(ids) <- body |> Map.get("messages", []) |> Enum.map(& &1["id"]),
         {:ok, messages} <- fetch_all(ids, token) do
      audit(user, "connection.gmail_searched", %{"count" => length(messages)})
      {:ok, messages}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  def get_message(%User{} = user, id) when is_binary(id) do
    with true <- Regex.match?(@id, id) || {:error, :not_found},
         {:ok, token} <- Connections.access_token(user, "google", [@scope]),
         {:ok, message} <- request(@messages <> "/" <> id, token, format: "full") do
      audit(user, "connection.gmail_message_read", %{"message_id" => id})
      {:ok, message |> summary() |> Map.put(:body, message |> Map.get("payload", %{}) |> body() |> bounded())}
    end
  end

  defp fetch_all(ids, token) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      with true <- is_binary(id) and Regex.match?(@id, id),
           {:ok, message} <-
             request(@messages <> "/" <> id, token,
               format: "metadata",
               metadataHeaders: "From",
               metadataHeaders: "To",
               metadataHeaders: "Subject",
               metadataHeaders: "Date"
             ) do
        {:cont, {:ok, [summary(message) | acc]}}
      else
        {:error, :not_found} -> {:cont, {:ok, acc}}
        {:error, _} = error -> {:halt, error}
        _ -> {:halt, {:error, :invalid_response}}
      end
    end)
    |> case do
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      error -> error
    end
  end

  defp summary(message) do
    headers = get_in(message, ["payload", "headers"]) || []

    %{
      id: message["id"],
      thread_id: message["threadId"],
      from: header(headers, "From"),
      to: header(headers, "To"),
      subject: header(headers, "Subject"),
      date: header(headers, "Date"),
      snippet: message["snippet"] || "",
      labels: message["labelIds"] || []
    }
  end

  # Prefer the plain-text part; fall back to tag-stripped HTML.
  defp body(payload) do
    parts = flatten(payload)

    case Enum.find(parts, &(&1["mimeType"] == "text/plain")) || Enum.find(parts, &(&1["mimeType"] == "text/html")) do
      %{"mimeType" => "text/html"} = part -> part |> decode() |> strip_html()
      %{} = part -> decode(part)
      nil -> ""
    end
  end

  defp flatten(%{"parts" => parts} = payload) when is_list(parts), do: [payload | Enum.flat_map(parts, &flatten/1)]
  defp flatten(%{} = payload), do: [payload]
  defp flatten(_), do: []

  defp decode(%{"body" => %{"data" => data}}) when is_binary(data) do
    data
    |> String.trim_trailing("=")
    |> Base.url_decode64(padding: false)
    |> case do
      {:ok, text} -> if String.valid?(text), do: text, else: ""
      :error -> ""
    end
  end

  defp decode(_), do: ""

  defp strip_html(html) do
    html
    |> String.replace(~r/<(script|style)[^>]*>.*?<\/\1>/is, " ")
    |> String.replace(~r/<br\s*\/?>|<\/p>|<\/div>/i, "\n")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/[ \t]+/, " ")
  end

  defp bounded(text), do: text |> String.trim() |> String.slice(0, @max_body)

  defp header(headers, name) when is_list(headers) do
    Enum.find_value(headers, "", fn
      %{"name" => key, "value" => value} when is_binary(key) and is_binary(value) ->
        if String.downcase(key) == String.downcase(name), do: value

      _ ->
        nil
    end)
  end

  defp request(url, token, params) do
    case Req.request(
           method: :get,
           url: url,
           auth: {:bearer, token},
           params: params,
           retry: false,
           redirect: false,
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} when status in [401, 403] -> {:error, :needs_authorization}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      _ -> {:error, :provider_unavailable}
    end
  end

  # Never record queries or message content: the audit trail shows that the
  # caller read their own mailbox, not what it contains.
  defp audit(user, action, metadata) do
    Audit.record(
      action,
      %{
        target_type: "user_connection",
        target_label: "google",
        metadata: Map.merge(%{"provider" => "google", "dashboard_path" => "/settings/connections"}, metadata)
      },
      actor: user
    )
  end
end
