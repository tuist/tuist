defmodule Atlas.Accounts.Workers.UpdateOverviewSummary do
  @moduledoc """
  Refreshes the persisted overview summary for a single account.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.Accounts
  alias Atlas.Audit
  alias Atlas.LLMs.Errors, as: LLMErrors

  @impl true
  def perform(%Oban.Job{} = job), do: perform(job, [])

  def perform(%Oban.Job{} = job, opts) do
    Audit.with_context(%{interface: "worker"}, fn -> do_perform(job, opts) end)
  end

  defp do_perform(%Oban.Job{args: %{"account_id" => account_id}}, opts) do
    refresh = Keyword.get(opts, :refresh, &Accounts.refresh_overview_summary/1)

    case refresh.(account_id) do
      {:ok, _account} -> :ok
      {:error, :not_found} -> {:cancel, :account_not_found}
      {:error, :llm_not_configured} -> {:cancel, :llm_not_configured}
      {:error, reason} -> LLMErrors.oban_error(reason)
    end
  end
end
