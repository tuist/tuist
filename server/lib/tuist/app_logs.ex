defmodule Tuist.AppLogs do
  @moduledoc """
  Forwards log lines uploaded by the Tuist iOS and macOS apps to Loki.

  The app authenticates with the user's token, so every line is attributed to
  the verified user and the organizations they belong to rather than to an
  identity the client reports. Lines are redacted again before forwarding.
  Nothing is stored by the server: the receiver is the cluster's Alloy Loki
  push endpoint, and Loki's retention applies. When no receiver is configured,
  as on self-hosted servers, uploads are accepted and discarded.
  """

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.AppLogs.Redaction
  alias Tuist.Environment
  alias Tuist.Repo

  @service_name "tuist-app"
  # Loki rejects a push with lines older than its ingestion window, which would
  # fail the whole batch on every retry. Device clocks can also run ahead, and
  # Loki rejects lines too far in the future, so those are clamped to now.
  @maximum_age_seconds 3 * 24 * 60 * 60

  def forward(%User{} = user, %{platform: platform} = app, entries) when is_list(entries) do
    with url when url not in [nil, ""] <- Environment.app_logs_receiver_url(),
         entries when entries != [] <- ingestible(entries) do
      push(url, payload(user, app, platform, entries))
    else
      _ -> :ok
    end
  end

  defp ingestible(entries) do
    now = DateTime.utc_now()
    oldest = DateTime.add(now, -@maximum_age_seconds, :second)

    entries
    |> Enum.reject(&DateTime.before?(&1.timestamp, oldest))
    |> Enum.map(&%{&1 | timestamp: Enum.min([&1.timestamp, now], DateTime)})
  end

  defp payload(user, app, platform, entries) do
    user = Repo.preload(user, :account)

    organization_handles =
      user
      |> Accounts.get_user_organization_accounts()
      |> Enum.map(& &1.account.name)
      |> Enum.sort()

    context = %{
      user_id: user.id,
      user_handle: user.account.name,
      organization_handles: Enum.join(organization_handles, ","),
      app_version: Map.get(app, :version),
      app_build: Map.get(app, :build),
      os_version: Map.get(app, :os_version)
    }

    values =
      entries
      |> Enum.sort_by(&DateTime.to_unix(&1.timestamp, :nanosecond))
      |> Enum.map(fn entry ->
        line =
          Map.merge(context, %{
            level: entry.level,
            source: entry.source,
            launch_id: Map.get(entry, :launch_id),
            message: Redaction.redact(entry.message)
          })

        [Integer.to_string(DateTime.to_unix(entry.timestamp, :nanosecond)), JSON.encode!(line)]
      end)

    %{
      streams: [
        %{
          stream: %{
            service_name: @service_name,
            environment: Environment.deploy_env_name(),
            platform: platform
          },
          values: values
        }
      ]
    }
  end

  # No retries: an ambiguous timeout can mean Alloy accepted the batch. The app
  # keeps the batch and uploads it again, which can duplicate lines but not
  # silently drop them.
  defp push(url, payload) do
    case Req.post(url,
           json: payload,
           retry: false,
           redirect: false,
           connect_options: [timeout: 1_000],
           receive_timeout: 5_000
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
