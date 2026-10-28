defmodule Atlas.Environments.Command do
  @moduledoc false
  use Atlas.Schema

  alias Atlas.Encrypted.Binary

  schema "environment_commands" do
    field :environment_id, Ecto.UUID
    field :environment_version, :integer
    field :thread_id, Ecto.UUID
    field :run_id, Ecto.UUID
    field :message_id, Ecto.UUID
    field :tool, :string
    field :arguments, Binary, redact: true
    field :environment_name, :string
    field :project_id, Ecto.UUID
    field :project_name, :string
    field :execution_timeout_seconds, :integer, default: 60
    field :execution_deadline, :utc_datetime_usec
    field :result_deadline, :utc_datetime_usec
    field :cancel_requested, :boolean, default: false
    field :progress_sequence, :integer, default: 0
    field :progress_output, Binary, redact: true
    field :continuation_message_id, Ecto.UUID
    field :digest, :string
    field :claim_token, Ecto.UUID, redact: true
    field :status, :string, default: "queued"
    field :result, Binary, redact: true
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
