defmodule Tuist.Runners.DispatchQueueEntry do
  @moduledoc false
  use Ecto.Schema

  alias Tuist.Accounts.Account

  schema "runner_dispatch_queue" do
    field :fleet_name, :string
    field :repo, :string

    belongs_to :account, Account

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
