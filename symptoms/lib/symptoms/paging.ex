defmodule Symptoms.Paging do
  @moduledoc """
  Delivers a page to Grafana IRM through a formatted-webhook integration.
  Paging is off by default: until `config :symptoms, :paging, enabled: true`
  with a `webhook_url`, a page is only logged (`decision.would_page` in the
  snapshot shows it). Grafana IRM is a delivery channel only; no state is
  read back from it.

  Config (`:paging`): `enabled` (false), `webhook_url`, `token` (optional
  bearer token), `link_base_url` (optional, prepended to the symptom id as
  `link_to_upstream_details`) and `req_options` (extra `Req` options, for
  tests).
  """

  require Logger

  @doc """
  Pages for a root symptom's snapshot. Returns `:sent`, `:logged` when
  paging is off, or `{:error, reason}`.
  """
  @spec page(map(), DateTime.t()) :: :sent | :logged | {:error, term()}
  def page(document, _at) do
    config = Application.get_env(:symptoms, :paging, [])
    url = config[:webhook_url]

    if enabled?(config, url) do
      post(url, symptom_body(document, config), config)
    else
      Logger.info("symptoms: would page #{document["symptom_id"]} (#{document["title"]})")
      :logged
    end
  end

  defp enabled?(config, url), do: config[:enabled] == true and is_binary(url) and url != ""

  defp symptom_body(document, config) do
    %{
      "alert_uid" => document["symptom_id"],
      "title" => document["title"],
      "state" => "alerting",
      "message" =>
        "P(degraded) #{document["p_degraded"]}, impact #{inspect(document["impact"])}, score #{document["score"]}",
      "link_to_upstream_details" => link(config[:link_base_url], document["symptom_id"]),
      "symptom" => Map.take(document, ~w(symptom_id revision symptom_key tier entity root suspected_change))
    }
  end

  defp post(url, body, config) do
    auth = if token = config[:token], do: [auth: {:bearer, token}], else: []
    options = [json: body, retry: false, receive_timeout: 10_000] ++ auth ++ Keyword.get(config, :req_options, [])

    case Req.post(url, options) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :sent
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp link(nil, _id), do: nil
  defp link(base, id), do: String.trim_trailing(base, "/") <> "/" <> id
end
