defmodule Tuist.Accounts.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for the Tuist account events
  """
  use PromEx.Plugin

  alias Tuist.Accounts
  alias Tuist.Telemetry

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, to_timeout(minute: 10))

    [
      Polling.build(
        :tuist_accounts_users_manual_metrics,
        poll_rate,
        {__MODULE__, :execute_accounts_users_count_telemetry_event, []},
        [
          last_value(
            [:tuist, :accounts, :users, :total],
            event_name: Telemetry.event_name_accounts_users_count(),
            description: "The total number of users",
            measurement: :total
          )
        ]
      ),
      Polling.build(
        :tuist_accounts_organizations_manual_metrics,
        poll_rate,
        {__MODULE__, :execute_accounts_organizations_count_telemetry_event, []},
        [
          last_value(
            [:tuist, :accounts, :organizations, :total],
            event_name: Telemetry.event_name_accounts_organizations_count(),
            description: "The total number of organizations",
            measurement: :total
          )
        ]
      )
    ]
  end

  def execute_accounts_users_count_telemetry_event do
    if Tuist.Repo.running?() do
      :telemetry.execute(
        Telemetry.event_name_accounts_users_count(),
        %{total: Accounts.get_users_count()},
        %{}
      )
    end
  end

  def execute_accounts_organizations_count_telemetry_event do
    if Tuist.Repo.running?() do
      :telemetry.execute(
        Telemetry.event_name_accounts_organizations_count(),
        %{total: Accounts.get_organizations_count()},
        %{}
      )
    end
  end
end
