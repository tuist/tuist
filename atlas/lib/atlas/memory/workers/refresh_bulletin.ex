defmodule Atlas.Memory.Workers.RefreshBulletin do
  @moduledoc """
  Synthesizes the memory bulletin for a given scope and writes it back via
  `Atlas.Memory.upsert_bulletin/3`.

  Two trigger paths:

    - `schedule_debounced/1` is called by `memory_save` after a node is
      created. Oban's `unique` dedupes calls within a debounce window so
      bursts of saves coalesce into a single refresh.

    - A daily cron entry guarantees the bulletin gets a refresh even on quiet
      days (or when the previous synthesis failed).

  Failures leave the previous bulletin untouched.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.LLMs.Errors, as: LLMErrors
  alias Atlas.Memory
  alias Atlas.Memory.BulletinSynthesizer

  require Logger

  @debounce_seconds 120

  def schedule_debounced(scope \\ :global) when scope in [:global, :channel] do
    %{"scope" => Atom.to_string(scope)}
    |> new(schedule_in: @debounce_seconds, unique: debounce_unique_options())
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def perform(%Oban.Job{args: args}) do
    scope = args |> Map.get("scope", "global") |> parse_scope()

    case BulletinSynthesizer.synthesize_global() do
      {:ok, :empty} ->
        :ok

      {:ok, body} when is_binary(body) ->
        case Memory.upsert_bulletin(scope, body) do
          {:ok, _bulletin} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :llm_not_configured} ->
        {:cancel, :llm_not_configured}

      {:error, reason} ->
        Logger.warning("Memory bulletin synthesis failed: #{inspect(reason)}")
        LLMErrors.oban_error(reason)
    end
  end

  defp parse_scope("channel"), do: :channel
  defp parse_scope(_), do: :global

  defp debounce_unique_options do
    [
      period: @debounce_seconds,
      fields: [:worker, :args],
      keys: [:scope],
      states: [:available, :scheduled, :retryable]
    ]
  end
end
