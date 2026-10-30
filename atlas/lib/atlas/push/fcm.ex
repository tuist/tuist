defmodule Atlas.Push.FCM do
  @moduledoc """
  Firebase Cloud Messaging HTTP v1 client for Android.

  Messages are data-only and high priority so the app can render the generic
  notification itself and drop messages addressed to an older registration.
  Result classification matches `Atlas.Push.APNs`. Tokens are invalidated only
  for `UNREGISTERED`, `SENDER_ID_MISMATCH`, or an `INVALID_ARGUMENT` whose field
  violation names `message.token`; any other invalid argument is a payload bug
  and must not prune registrations.
  """

  alias Atlas.Push.APNs
  alias Atlas.Push.Config
  alias Atlas.Push.Credentials

  @origin "https://fcm.googleapis.com"

  def origin, do: @origin

  def deliver(%{token: token}, data, opts) do
    with {:ok, fcm} <- Config.fcm(),
         {:ok, access_token} <- Credentials.fcm_token(fcm) do
      ttl = max(DateTime.diff(Keyword.fetch!(opts, :expires_at), DateTime.utc_now()), 0)

      request =
        Keyword.merge(
          [
            json: %{
              "message" => %{
                "token" => token,
                "data" => data,
                # No collapse_key: FCM keeps only four per device. The app
                # deduplicates with the notification_id in the data instead.
                "android" => %{"priority" => "HIGH", "ttl" => "#{ttl}s"}
              }
            },
            auth: {:bearer, access_token},
            retry: false,
            redirect: false,
            receive_timeout: 10_000
          ],
          Config.req_options()
        )

      "#{@origin}/v1/projects/#{fcm.project_id}/messages:send"
      |> Req.post(request)
      |> classify(fcm)
    else
      {:error, :not_configured} -> {:error, :fcm_not_configured}
      {:error, :fcm_credentials_rejected} -> {:error, :fcm_credentials_rejected}
      {:error, _reason} -> {:retry, nil}
    end
  end

  defp classify({:ok, %Req.Response{status: 200}}, _fcm), do: :ok

  defp classify({:ok, %Req.Response{status: 401}}, fcm) do
    Credentials.invalidate(:fcm, fcm)
    {:retry, nil}
  end

  defp classify({:ok, %Req.Response{status: status} = response}, _fcm) when status in [429, 500, 503],
    do: {:retry, APNs.retry_after(response)}

  defp classify({:ok, %Req.Response{status: status, body: body}}, _fcm) when status in [400, 403, 404] do
    details = error_details(body)

    cond do
      error_code(details) in ["UNREGISTERED", "SENDER_ID_MISMATCH"] -> {:invalid_token, []}
      token_violation?(details) -> {:invalid_token, []}
      status == 403 -> {:error, :fcm_credentials_rejected}
      true -> {:error, :fcm_rejected}
    end
  end

  defp classify({:ok, %Req.Response{}}, _fcm), do: {:error, :fcm_rejected}
  defp classify({:error, _exception}, _fcm), do: {:retry, nil}

  defp error_details(%{"error" => %{"details" => details}}) when is_list(details), do: details
  defp error_details(_body), do: []

  defp error_code(details) do
    Enum.find_value(details, fn
      %{"@type" => "type.googleapis.com/google.firebase.fcm.v1.FcmError", "errorCode" => code} -> code
      _ -> nil
    end)
  end

  defp token_violation?(details) do
    error_code(details) == "INVALID_ARGUMENT" and
      Enum.any?(details, fn
        %{"@type" => "type.googleapis.com/google.rpc.BadRequest", "fieldViolations" => violations}
        when is_list(violations) ->
          Enum.any?(violations, &match?(%{"field" => "message.token"}, &1))

        _ ->
          false
      end)
  end
end
