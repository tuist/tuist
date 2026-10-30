defmodule Atlas.Signals.Providers do
  @moduledoc false

  @gmail "https://gmail.googleapis.com/gmail/v1/users/me/messages"
  @slack "https://slack.com/api/search.messages"

  def fetch(%{"provider" => "gmail"} = config, authorize, state) do
    params = [
      q: "(#{config["query"]}) -in:drafts -in:sent after:#{state["start"] - 1} before:#{state["end"] + 1}",
      maxResults: 10
    ]

    params = if state["page"], do: Keyword.put(params, :pageToken, state["page"]), else: params

    with {:ok, body} <- request(@gmail, authorize, params),
         messages when is_list(messages) and length(messages) <= 10 <- Map.get(body, "messages", []),
         {:ok, page} <- page_token(body["nextPageToken"]) do
      Enum.reduce_while(messages, {:ok, []}, fn message, {:ok, envelopes} ->
        case gmail_message(message, authorize) do
          {:ok, envelope} -> {:cont, {:ok, [envelope | envelopes]}}
          {:error, :not_found} -> {:cont, {:ok, envelopes}}
          {:error, _} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, envelopes} -> {:ok, in_window(envelopes, state), page}
        error -> error
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  def fetch(%{"provider" => "slack"} = config, authorize, state) do
    # Slack's documented search syntax uses dates. Widen across time zones and
    # enforce the exact UTC window locally; overlapping polls deduplicate on ID.
    after_date = state["start"] |> DateTime.from_unix!() |> DateTime.to_date() |> Date.add(-1)
    before_date = state["end"] |> DateTime.from_unix!() |> DateTime.to_date() |> Date.add(2)

    params = [
      query: "#{config["query"]} after:#{after_date} before:#{before_date}",
      count: 100,
      sort: "timestamp",
      sort_dir: "asc",
      cursor: state["page"] || "*"
    ]

    with {:ok, %{"ok" => true, "messages" => %{"matches" => matches}} = body} <- request(@slack, authorize, params),
         true <- is_list(matches) and length(matches) <= 100,
         {:ok, page} <- slack_cursor(body) do
      Enum.reduce_while(matches, {:ok, []}, fn message, {:ok, envelopes} ->
        case slack_message(message) do
          {:ok, envelope} -> {:cont, {:ok, [envelope | envelopes]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, envelopes} -> {:ok, in_window(envelopes, state), page}
        error -> error
      end
    else
      {:ok, %{"error" => "ratelimited"}} ->
        {:error, {:rate_limited, 60}}

      {:ok, %{"error" => error}} when error in ~w(invalid_auth token_revoked missing_scope account_inactive) ->
        {:error, :needs_authorization}

      {:error, _} = error ->
        error

      _ ->
        {:error, :invalid_response}
    end
  end

  defp gmail_message(%{"id" => id}, authorize) when is_binary(id) do
    with true <- Regex.match?(~r/\A[A-Za-z0-9_-]{1,100}\z/, id),
         {:ok, %{"id" => ^id, "threadId" => thread, "internalDate" => millis, "snippet" => snippet} = message} <-
           request(@gmail <> "/" <> id, authorize, [
             {:format, "metadata"},
             {:metadataHeaders, "Subject"},
             {:metadataHeaders, "From"}
           ]),
         true <- is_binary(thread) and byte_size(thread) <= 100 and is_binary(snippet),
         true <- is_binary(millis) and byte_size(millis) <= 16,
         {timestamp, ""} <- Integer.parse(millis),
         {:ok, occurred_at} <- DateTime.from_unix(timestamp, :millisecond) do
      headers =
        case message["payload"] do
          %{"headers" => headers} -> headers
          _ -> []
        end

      subject = header(headers, "Subject")
      sender = header(headers, "From")

      {:ok,
       envelope("gmail.message", "gmail:#{id}", "gmail:#{thread}", occurred_at, subject, snippet, %{
         "sender" => text(sender, 200),
         "message_id" => id,
         "thread_id" => thread,
         "excerpt" => text(snippet, 1000)
       })}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  defp gmail_message(_, _), do: {:error, :invalid_response}

  defp slack_message(%{"ts" => ts, "text" => body, "channel" => %{"id" => channel}} = message)
       when is_binary(ts) and is_binary(body) and is_binary(channel) do
    with true <- byte_size(channel) <= 100 and Regex.match?(~r/\A[0-9]{1,12}\.[0-9]{1,6}\z/, ts),
         [seconds, micros] <- String.split(ts, "."),
         {:ok, occurred_at} <-
           DateTime.from_unix(
             String.to_integer(seconds) * 1_000_000 + String.to_integer(String.pad_trailing(micros, 6, "0")),
             :microsecond
           ) do
      digest = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
      parent = message["thread_ts"] || ts

      if is_binary(parent) and byte_size(parent) <= 50 do
        {:ok,
         envelope(
           "slack.message",
           "slack:#{channel}:#{ts}:#{digest}",
           "slack:#{channel}:#{parent}",
           occurred_at,
           body,
           body,
           %{"channel_id" => channel, "timestamp" => ts, "excerpt" => text(body, 1000)}
         )}
      else
        {:error, :invalid_response}
      end
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp slack_message(_), do: {:error, :invalid_response}

  defp envelope(type, id, correlation, at, title, summary, data) do
    title = title |> text(100) |> String.trim()
    summary = summary |> text(500) |> String.trim()

    %{
      "type" => type,
      "schema_version" => 1,
      "external_id" => id,
      "correlation_key" => correlation,
      "occurred_at" => DateTime.to_iso8601(at),
      "title" => if(title == "", do: "New message", else: title),
      "summary" => if(summary == "", do: "New message received", else: summary),
      "data" => data
    }
  end

  defp in_window(envelopes, state) do
    Enum.filter(envelopes, fn envelope ->
      {:ok, at, _} = DateTime.from_iso8601(envelope["occurred_at"])
      seconds = DateTime.to_unix(at)
      seconds >= state["start"] and seconds <= state["end"]
    end)
  end

  defp text(value, limit), do: value |> String.replace(~r/[\x00-\x1F\x7F]/u, " ") |> String.slice(0, limit)

  defp header(headers, name) when is_list(headers) do
    Enum.find_value(headers, "", fn
      %{"name" => key, "value" => value} when is_binary(key) and is_binary(value) ->
        if String.downcase(key) == String.downcase(name), do: value

      _ ->
        nil
    end)
  end

  defp header(_, _), do: ""

  defp page_token(value) when value in [nil, ""], do: {:ok, nil}
  defp page_token(value) when is_binary(value) and byte_size(value) <= 4096, do: {:ok, value}
  defp page_token(_), do: {:error, :invalid_response}

  defp slack_cursor(body) do
    case body["response_metadata"] do
      %{"next_cursor" => cursor} -> page_token(cursor)
      nil -> {:ok, nil}
      _ -> {:error, :invalid_response}
    end
  end

  defp request(url, authorize, params) do
    with {:ok, token} <- authorize.(), do: request_authorized(url, token, params)
  end

  defp request_authorized(url, token, params) do
    case Req.request(
           method: :get,
           url: url,
           auth: {:bearer, token},
           params: params,
           retry: false,
           redirect: false,
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} when status in [401, 403] ->
        {:error, :needs_authorization}

      {:ok, %{status: 429} = response} ->
        seconds = response |> Req.Response.get_header("retry-after") |> List.first() |> then(&Integer.parse(&1 || "60"))

        {:error,
         {:rate_limited,
          case seconds do
            {value, ""} -> min(max(value, 1), 3600)
            _ -> 60
          end}}

      _ ->
        {:error, :provider_unavailable}
    end
  end
end
