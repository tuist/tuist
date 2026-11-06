defmodule Atlas.Automations.Workers.ScheduleRuns do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3, tags: ["automation"]

  alias Atlas.Automations

  @impl Oban.Worker
  def perform(_job), do: Automations.schedule_due()
end
