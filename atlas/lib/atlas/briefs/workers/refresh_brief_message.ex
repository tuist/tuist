defmodule Atlas.Briefs.Workers.RefreshBriefMessage do
  use Oban.Worker, queue: :briefs, max_attempts: 5

  alias Atlas.Briefs
  alias Atlas.Briefs.Notifier

  @impl true
  def perform(%Oban.Job{args: %{"brief_id" => brief_id}}) do
    case Briefs.get_brief(brief_id) do
      nil -> {:discard, :not_found}
      brief -> Notifier.notify(brief)
    end
  end
end
