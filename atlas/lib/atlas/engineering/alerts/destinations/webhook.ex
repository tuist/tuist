defmodule Atlas.Engineering.Alerts.Destinations.Webhook do
  @moduledoc """
  Sends an alert to an HTTPS endpoint as a signed JSON envelope.

  The receiver validates the request by recomputing an HMAC-SHA256 of the
  raw body with the rule's `webhook_signing_secret` and comparing it
  against the `X-Atlas-Signature` header. Envelopes carry an
  `Atlas-Delivery-Id` header (an opaque UUID) that lets receivers dedupe
  retries.
  """

  alias Atlas.Engineering.Alerts.Rule
  alias Atlas.Engineering.Errors.Issue
  alias AtlasWeb.Endpoint

  @user_agent "Atlas-Alerts/1.0"

  def deliver(%Rule{} = rule, %Issue{} = issue, reason, opts \\ []) do
    body = build_body(rule, issue, reason)
    encoded = JSON.encode!(body)
    signature = sign(encoded, rule.webhook_signing_secret)

    headers = [
      {"content-type", "application/json"},
      {"user-agent", @user_agent},
      {"x-atlas-signature", "sha256=" <> signature},
      {"x-atlas-event", "alert.fired"},
      {"atlas-delivery-id", body["delivery_id"]}
    ]

    request = Keyword.get(opts, :request, &default_request/3)

    case request.(rule.webhook_url, headers, encoded) do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end

  defp default_request(url, headers, body) do
    case Req.post(url, headers: headers, body: body, receive_timeout: :timer.seconds(10)) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:webhook_http, status}}
      {:error, reason} -> {:error, {:webhook_transport, reason}}
    end
  end

  defp build_body(%Rule{} = rule, %Issue{} = issue, reason) do
    %{
      "delivery_id" => Ecto.UUID.generate(),
      "event" => "alert.fired",
      "rule" => %{
        "id" => rule.id,
        "name" => rule.name,
        "tier" => Atom.to_string(rule.tier),
        "trigger" => Atom.to_string(rule.trigger || :unknown),
        "reason" => reason_string(reason)
      },
      "issue" => %{
        "id" => issue.id,
        "title" => issue.title,
        "culprit" => issue.culprit,
        "level" => issue.level && Atom.to_string(issue.level),
        "status" => issue.status && Atom.to_string(issue.status),
        "event_count" => issue.event_count,
        "first_seen" => issue.first_seen && DateTime.to_iso8601(issue.first_seen),
        "last_seen" => issue.last_seen && DateTime.to_iso8601(issue.last_seen),
        "url" => Endpoint.url() <> "/engineering/errors/#{issue.id}"
      },
      "project" => %{"id" => rule.project_id},
      "sent_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp reason_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_string(reason) when is_binary(reason), do: reason
  defp reason_string(_other), do: "unknown"

  defp sign(body, secret) when is_binary(body) and is_binary(secret) do
    :hmac
    |> :crypto.mac(:sha256, secret, body)
    |> Base.encode16(case: :lower)
  end
end
