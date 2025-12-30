defmodule Tuist.Projects.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for the Tuist account events
  """
  use PromEx.Plugin

  alias Tuist.Projects
  alias Tuist.Telemetry

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, to_timeout(minute: 10))

    [
      Polling.build(
        :tuist_projects_manual_metrics,
        poll_rate,
        {__MODULE__, :execute_projects_count_telemetry_event, []},
        [
          last_value(
            [:tuist, :projects, :total],
            event_name: Telemetry.event_name_projects_count(),
            description: "The total number of projects",
            measurement: :total
          )
        ]
      )
    ]
  end

  def execute_projects_count_telemetry_event do
    if Tuist.Repo.running?() do
      :telemetry.execute(
        Telemetry.event_name_projects_count(),
        %{total: Projects.get_projects_count()},
        %{}
      )
    end
  end
end
