defmodule Atlas.Signals.Workers.SchedulePolls do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 3, tags: ["signals"]

  alias Atlas.Signals.Polling

  @impl Oban.Worker
  def perform(_job), do: Polling.schedule_due()
end
