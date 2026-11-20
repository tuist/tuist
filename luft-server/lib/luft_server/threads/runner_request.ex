defmodule LuftServer.Threads.RunnerRequest do
  @moduledoc "A durable pending, claimed or completed operation on a runner."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "thread_runner_requests" do
    field :runner_id, :binary_id
    field :run_id, :binary_id
    field :run_attempt, :integer
    field :op, :string
    field :payload, :map, redact: true
    field :status, :string, default: "pending"
    field :response, :map, redact: true
    field :claimed_at, :utc_datetime
    field :expires_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
