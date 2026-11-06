defmodule Pulse.Storage.S3.RetentionSupervision do
  @moduledoc false
  use Pulse.Runtime.Supervision

  alias Pulse.Runtime.Supervision, as: Supervisor
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3.RetentionScope
  alias Pulse.Storage.S3.RetentionTasks
  alias Pulse.Storage.S3.RetentionWorker

  def start_link(config), do: Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  @impl true
  def init(config) do
    Supervisor.init(
      [
        %{id: RetentionScope, start: {:pg, :start_link, [RetentionScope]}},
        {Task.Supervisor, name: RetentionTasks, max_children: 1},
        {RetentionWorker, config}
      ],
      strategy: :rest_for_one
    )
  end
end
