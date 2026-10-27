defmodule Atlas.Granola.Workers.SyncNotes do
  @moduledoc """
  Syncs Granola notes into account meeting timeline events.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    tags: ["granola", "meetings"]

  alias Atlas.Granola
  alias Atlas.LLMs.Errors, as: LLMErrors

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: perform(job, [])

  def perform(%Oban.Job{args: args}, opts) do
    sync_notes = Keyword.get(opts, :sync_notes, &Granola.sync_notes/1)
    sync_opts = [sync_mode: sync_mode(args)]

    case call_sync_notes(sync_notes, sync_opts) do
      {:ok, _result} -> :ok
      :disabled -> {:cancel, :granola_sync_disabled}
      {:error, reason} -> LLMErrors.oban_error(reason)
    end
  end

  defp sync_mode(%{"mode" => "backfill"}), do: :backfill
  defp sync_mode(%{mode: "backfill"}), do: :backfill
  defp sync_mode(_args), do: :incremental

  defp call_sync_notes(sync_notes, sync_opts) when is_function(sync_notes, 1), do: sync_notes.(sync_opts)
  defp call_sync_notes(sync_notes, _sync_opts) when is_function(sync_notes, 0), do: sync_notes.()
end
