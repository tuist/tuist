defmodule Tuist.Sandboxes.AgentSession do
  @moduledoc """
  A Managed Agents session Tuist started on an account's connected
  environment. Anthropic owns the conversation; this row keeps the ids
  needed to follow it (`anthropic_session_id`, `anthropic_agent_id`), what
  was asked (`prompt`, repository), the budget and the last status the
  server saw. `sandbox_id` is bound by the router once the session's first
  work item creates its VM.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Sandbox

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sandbox_agent_sessions" do
    field :anthropic_session_id, :string
    field :anthropic_agent_id, :string
    field :title, :string
    field :prompt, :string
    field :repository_url, :string
    field :repository_ref, :string
    field :model, :string
    field :budget_cents, :integer
    field :last_status, :string
    field :last_stop_reason, :string

    belongs_to :account, Account
    belongs_to :agent_environment, AgentEnvironment
    belongs_to :sandbox, Sandbox, type: :binary_id
    belongs_to :created_by_user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Validates what a caller may ask for. Run before the session is created
  at Anthropic so a bad request never leaves an orphaned session there.
  """
  def params_changeset(agent_session, attrs) do
    agent_session
    |> cast(attrs, [:prompt, :title, :repository_url, :repository_ref, :model, :budget_cents])
    |> validate_required([:prompt])
    |> validate_length(:title, max: 255)
    |> validate_length(:model, min: 1, max: 255)
    |> validate_length(:repository_url, max: 512)
    |> validate_format(:repository_url, ~r{\Ahttps://\S+\z})
    |> validate_length(:repository_ref, max: 255)
    |> validate_format(:repository_ref, ~r{\A[A-Za-z0-9][A-Za-z0-9._/-]*\z})
    |> validate_number(:budget_cents, greater_than: 0)
  end

  def create_changeset(agent_session, attrs) do
    agent_session
    |> params_changeset(attrs)
    |> cast(attrs, [
      :account_id,
      :agent_environment_id,
      :anthropic_session_id,
      :anthropic_agent_id,
      :last_status,
      :created_by_user_id
    ])
    |> validate_required([:account_id, :agent_environment_id, :anthropic_session_id, :anthropic_agent_id])
    |> unique_constraint(:anthropic_session_id)
  end

  def update_changeset(agent_session, attrs) do
    cast(agent_session, attrs, [:sandbox_id, :last_status, :last_stop_reason])
  end
end
