defmodule Atlas.Finance.Workers.CategorizeTransactions do
  @moduledoc """
  Runs the finance transaction categorization agent.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.Finance
  alias Atlas.LLMs.Errors, as: LLMErrors

  def perform(%Oban.Job{}) do
    case Finance.categorize_transactions() do
      {:ok, _summary} -> :ok
      {:error, :llm_not_configured} -> {:cancel, :llm_not_configured}
      {:error, reason} -> LLMErrors.oban_error(reason)
    end
  end
end
