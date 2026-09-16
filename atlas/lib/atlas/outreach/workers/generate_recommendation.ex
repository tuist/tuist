defmodule Atlas.Outreach.Workers.GenerateRecommendation do
  @moduledoc """
  Generates the next guided outreach action for one contact.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.Audit
  alias Atlas.LLMs.Errors, as: LanguageModelErrors
  alias Atlas.Outreach

  @impl true
  def perform(%Oban.Job{args: %{"contact_id" => contact_id} = args}) do
    Audit.with_context(
      %{interface: "worker", metadata: %{"trigger" => Map.get(args, "source", "system")}},
      fn ->
        case Outreach.generate_recommendation(contact_id) do
          {:ok, _recommendation} -> :ok
          {:error, :not_found} -> {:cancel, :contact_not_found}
          {:error, :llm_not_configured} -> {:cancel, :llm_not_configured}
          {:error, reason} -> LanguageModelErrors.oban_error(reason)
        end
      end
    )
  end
end
