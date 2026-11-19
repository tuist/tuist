defmodule Atlas.Labels.Session do
  @moduledoc false
  use Atlas.Schema

  alias Atlas.Labels.Job
  alias Atlas.Users.User

  schema "label_sessions" do
    belongs_to :owner, User
    field :relay_token_hash, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    field :relay, :map
    has_many :jobs, Job
    timestamps(type: :utc_datetime_usec)
  end
end
