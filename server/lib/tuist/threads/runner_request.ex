defmodule Tuist.Threads.RunnerRequest do
  @moduledoc """
  One operation a thread asked a runner to perform. `pending` until the
  runner's poll claims it, `claimed` until it answers, then `done` with the
  response. The waiting thread deletes the row once it read the response.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "thread_runner_requests" do
    field :runner_id, :binary_id
    field :op, :string
    # File contents, commands and their output: never logged.
    field :payload, :map, redact: true
    field :status, :string, default: "pending"
    field :response, :map, redact: true
    field :claimed_at, :utc_datetime
    field :expires_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
