defmodule Atlas.Engineering.Errors.Summaries do
  @moduledoc """
  Error-summary reporting.

  TODO(atlas): port the full summary pipeline once Atlas has an equivalent
  of Hive's LangChain-driven summary agent and a Slack delivery channel.
  For now the module keeps a minimal API so callers compile and the
  scheduler can be wired incrementally.
  """

  alias Atlas.Engineering.Errors.SummarySettings
  alias Atlas.Repo

  @settings_id "singleton"

  def load_settings do
    case Repo.get(SummarySettings, @settings_id) do
      nil -> %SummarySettings{id: @settings_id}
      %SummarySettings{} = settings -> settings
    end
  end

  def upsert_settings(attrs) do
    settings = load_settings()

    settings
    |> SummarySettings.changeset(Map.put(attrs, "id", @settings_id))
    |> Repo.insert_or_update()
  end

  def reconcile(_opts \\ []) do
    {:error, :not_implemented}
  end
end
