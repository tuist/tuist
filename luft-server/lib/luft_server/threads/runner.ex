defmodule LuftServer.Threads.Runner do
  @moduledoc "A person's own machine that their threads can run on."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "thread_runners" do
    field :user_id, :integer
    field :name, :string
    field :platform, :string
    field :token_hash, :binary, redact: true
    field :capabilities, :map, default: %{}
    field :last_seen_at, :utc_datetime
    field :revoked_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
