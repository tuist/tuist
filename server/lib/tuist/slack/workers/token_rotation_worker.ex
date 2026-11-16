defmodule Tuist.Slack.Workers.TokenRotationWorker do
  @moduledoc """
  An hourly job that keeps Slack installation tokens rotated.

  Rotated access tokens expire after 12 hours. Each run refreshes every token
  that expires within the next six hours, so each token gets several hourly
  attempts before `Tuist.Slack.installation_access_token/1` has to refresh on
  use, and a Slack OAuth outage of a few hours costs nothing.

  Each run also exchanges up to five long-lived tokens from before token
  rotation (`refresh_token` is null) for a rotating pair, so a fleet moves
  over gradually and a problem shows up in a few installations first. Only
  successful exchanges count toward that cap: installations that can never be
  exchanged (uninstalled app, revoked token) are retried every run without
  holding back the rest. Slack answers `token_rotation_not_enabled` for every
  installation while rotation is off for the app, such as a self-hosted Slack
  app, so the first such answer ends the run's exchanges and those
  installations keep their long-lived token.
  """
  use Oban.Worker, max_attempts: 1

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Slack
  alias Tuist.Slack.Installation

  require Logger

  @refresh_margin_seconds 6 * 60 * 60
  @exchanges_per_run 5

  # Failures that retrying will not fix: the installation needs to be
  # reconnected, or the server's Slack client credentials are wrong.
  @permanent_errors ~w(invalid_refresh_token token_already_exchanged invalid_auth token_revoked account_inactive
                       bad_client_secret invalid_client_id)

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), @refresh_margin_seconds, :second)

    from(i in Installation,
      where: not is_nil(i.refresh_token) and i.access_token_expires_at <= ^cutoff,
      select: struct(i, [:id, :account_id, :refresh_token])
    )
    |> Repo.all()
    |> Enum.each(&rotate(&1, "refresh"))

    _exchanged =
      from(i in Installation,
        where: is_nil(i.refresh_token),
        order_by: i.inserted_at,
        select: struct(i, [:id, :account_id, :refresh_token])
      )
      |> Repo.all()
      |> Enum.reduce_while(0, fn installation, exchanged ->
        case rotate(installation, "exchange") do
          :rotated when exchanged + 1 >= @exchanges_per_run -> {:halt, exchanged + 1}
          :rotated -> {:cont, exchanged + 1}
          :rotation_not_enabled -> {:halt, exchanged}
          :failed -> {:cont, exchanged}
        end
      end)

    :ok
  end

  defp rotate(installation, operation) do
    case Slack.rotate_installation_token(installation, @refresh_margin_seconds) do
      {:ok, _installation} ->
        :rotated

      {:error, "token_rotation_not_enabled"} ->
        :rotation_not_enabled

      {:error, reason} ->
        message =
          "Slack token #{operation} failed for installation #{installation.id} (account #{installation.account_id}): #{inspect(reason)}"

        Logger.warning(message)

        if reason in @permanent_errors do
          Sentry.capture_message("Slack token #{operation} failed permanently",
            level: :error,
            extra: %{installation_id: installation.id, account_id: installation.account_id, reason: reason}
          )
        end

        :failed
    end
  end
end
