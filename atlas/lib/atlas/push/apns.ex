defmodule Atlas.Push.APNs do
  @moduledoc """
  Apple Push Notification service client using token-based provider
  authentication over the dedicated HTTP/2 pools in `Atlas.HTTP`.

  Results are classified for the delivery worker:

    * `:ok`
    * `{:invalid_token, opts}`: definitive token failure (410 `Unregistered`, with
      Apple's last-invalid timestamp when supplied, or 400 `BadDeviceToken` for
      the stored environment).
    * `{:retry, retry_after_seconds | nil}`: throttling, provider unavailability,
      transport failure, or an expired provider token (which is dropped first).
    * `{:error, reason}`: configuration or payload failures that retrying cannot
      fix. Tokens are never invalidated for these.

  Reasons are fixed atoms; response bodies and tokens are never logged.
  """

  alias Atlas.Push.Config
  alias Atlas.Push.Credentials

  @hosts %{"production" => "https://api.push.apple.com", "sandbox" => "https://api.sandbox.push.apple.com"}

  def origins, do: Map.values(@hosts)

  def deliver(%{token: token, environment: environment}, payload, opts) when is_map_key(@hosts, environment) do
    with {:ok, apns} <- Config.apns_for(environment),
         {:ok, provider_token} <- Credentials.apns_token(apns) do
      live_activity? = Keyword.get(opts, :live_activity, false)
      topic = if live_activity?, do: Config.apns_topic() <> ".push-type.liveactivity", else: Config.apns_topic()

      request =
        Keyword.merge(
          [
            json: payload,
            headers: [
              {"authorization", "bearer " <> provider_token},
              {"apns-topic", topic},
              {"apns-push-type", if(live_activity?, do: "liveactivity", else: "alert")},
              {"apns-priority", if(live_activity?, do: "5", else: "10")},
              {"apns-expiration", Integer.to_string(DateTime.to_unix(Keyword.fetch!(opts, :expires_at)))},
              {"apns-collapse-id", Keyword.fetch!(opts, :collapse_id)}
            ],
            retry: false,
            redirect: false,
            receive_timeout: 10_000
          ],
          Config.req_options()
        )

      @hosts
      |> Map.fetch!(environment)
      |> Kernel.<>("/3/device/" <> token)
      |> Req.post(request)
      |> classify(apns)
    else
      {:error, :not_configured} -> {:error, :apns_not_configured}
      {:error, _reason} -> {:retry, nil}
    end
  end

  defp classify({:ok, %Req.Response{status: 200}}, _apns), do: :ok

  defp classify({:ok, %Req.Response{status: 410} = response}, _apns),
    do: {:invalid_token, unregistered_at: unregistered_at(response.body)}

  defp classify({:ok, %Req.Response{status: 400, body: %{"reason" => "BadDeviceToken"}}}, _apns),
    do: {:invalid_token, []}

  defp classify({:ok, %Req.Response{status: 403, body: %{"reason" => "ExpiredProviderToken"}}}, apns) do
    Credentials.invalidate(:apns, apns)
    {:retry, nil}
  end

  defp classify({:ok, %Req.Response{status: status} = response}, _apns) when status in [429, 500, 503],
    do: {:retry, retry_after(response)}

  defp classify({:ok, %Req.Response{status: 403}}, _apns), do: {:error, :apns_credentials_rejected}
  defp classify({:ok, %Req.Response{status: 413}}, _apns), do: {:error, :apns_payload_too_large}
  defp classify({:ok, %Req.Response{}}, _apns), do: {:error, :apns_rejected}
  defp classify({:error, _exception}, _apns), do: {:retry, nil}

  defp unregistered_at(%{"timestamp" => milliseconds}) when is_integer(milliseconds) do
    case DateTime.from_unix(milliseconds, :millisecond) do
      {:ok, at} -> at
      _ -> nil
    end
  end

  defp unregistered_at(_body), do: nil

  @doc false
  def retry_after(%Req.Response{} = response) do
    case Req.Response.get_header(response, "retry-after") do
      [value | _] ->
        case Integer.parse(value) do
          {seconds, ""} when seconds >= 0 -> seconds
          _ -> nil
        end

      [] ->
        nil
    end
  end
end
