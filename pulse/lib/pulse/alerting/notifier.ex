defmodule Pulse.Alerting.Notifier do
  @moduledoc "At-least-once native Slack delivery from committed bounded per-target outboxes."
  alias Pulse.Alerting.{Canonical, Repository, Targets}

  @lease_ns 30_000_000_000

  def run_once(tenant, id, opts \\ []) do
    with {:ok, head, _} <- Repository.load(tenant, id, opts) do
      Enum.reduce(Map.keys(Map.get(head, "outboxes", %{})), 0, &deliver(tenant, id, &1, &2, opts))
    end
  end

  defp deliver(tenant, id, version, count, opts) do
    nonce = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    now = Keyword.get_lazy(opts, :timestamp_ns, fn -> System.system_time(:nanosecond) end)
    result = Repository.update_outbox(tenant, id, version, &claim(&1, nonce, now), opts)

    case result do
      {:ok, box} ->
        deliver_claimed(tenant, id, version, nonce, box, opts)
        count + 1

      _ ->
        count
    end
  end

  defp claim(%{"queue" => []}, _nonce, _now), do: {:error, :empty_outbox}

  defp claim(box, nonce, now) do
    previous = box["claim"]

    if previous && String.to_integer(previous["expires_ns"]) > now do
      {:error, :notification_claimed}
    else
      {:ok,
       Map.put(box, "claim", %{
         "nonce" => nonce,
         "expires_ns" => Integer.to_string(now + @lease_ns),
         "event_digest" => hd(box["queue"])["digest"]
       })}
    end
  end

  defp deliver_claimed(tenant, id, version, nonce, box, opts) do
    with {:ok, event} <- Repository.revision(tenant, id, hd(box["queue"]), opts),
         {:ok, url} <- Targets.resolve(box["target"]),
         :ok <- post(url, payload(event), opts) do
      acknowledge(tenant, id, version, nonce, opts, 3)
    else
      _ -> {:error, :notification_failed}
    end
  end

  defp acknowledge(_tenant, _id, _version, _nonce, _opts, 0), do: {:error, :outbox_conflict}

  defp acknowledge(tenant, id, version, nonce, opts, attempts) do
    case Repository.update_outbox(tenant, id, version, &ack(&1, nonce), opts) do
      {:error, :outbox_conflict} -> acknowledge(tenant, id, version, nonce, opts, attempts - 1)
      result -> result
    end
  end

  defp ack(%{"claim" => %{"nonce" => nonce, "event_digest" => digest}, "queue" => [first | rest]} = box, nonce) do
    if first["digest"] == digest,
      do: {:ok, Map.merge(box, %{"claim" => nil, "queue" => rest})},
      else: {:error, :outbox_conflict}
  end

  defp ack(_, _), do: {:error, :outbox_conflict}

  defp post(url, body, opts) do
    http_options = Keyword.get(opts, :http_options, [])
    options = Keyword.merge(http_options, url: url, json: body, retry: false, redirect: false, receive_timeout: 5000)

    case Req.post(options) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      _ -> {:error, :notification_failed}
    end
  end

  @doc false
  def payload(event) do
    instance = event["instance"]
    title = String.upcase(event["type"]) <> ": " <> instance["labels"]["alertname"]
    # All producer-controlled text uses Slack plain_text, never mrkdwn or mention parsing.
    details = instance["labels"] |> Enum.sort() |> Enum.map_join("\n", fn {key, value} -> key <> "=" <> value end)
    text = String.slice(title <> "\n" <> details <> "\nvalue=" <> instance["value"], 0, 2800)

    %{
      "blocks" => [
        %{"type" => "section", "text" => %{"type" => "plain_text", "text" => text, "emoji" => false}},
        %{
          "type" => "context",
          "elements" => [%{"type" => "plain_text", "text" => "Pulse event " <> event["event_id"], "emoji" => false}]
        }
      ],
      "text" => "Pulse alert " <> Canonical.hash(event["event_id"]),
      "unfurl_links" => false,
      "unfurl_media" => false
    }
  end
end
