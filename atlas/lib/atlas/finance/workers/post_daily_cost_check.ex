defmodule Atlas.Finance.Workers.PostDailyCostCheck do
  @moduledoc """
  Compatibility entry point for the shared daily leadership brief.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.Briefs

  @impl true
  def perform(%Oban.Job{}) do
    case Briefs.generate_for_audience("leadership", "daily") do
      {:ok, _brief} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
