defmodule Tuist.Runners.Pool do
  @moduledoc """
  Customer runner-pool config. Stored in Postgres
  (`Tuist.Runners.Pools`); `Tuist.Runners.PoolReconciler` derives the
  matching `RunnerPool` CR in the cluster's runners namespace from it.
  The CR is the K8s consumer's view; this schema is the source of
  truth.

  Two roles:
    * `:customer` — per-org reserved capacity. `account_id` + `owner`
      are required; `min_warm` is the customer-visible knob.
    * `:shared_warm` — cluster-wide standby pool the dispatch endpoint
      claims Bursts against. `account_id` is nil, `owner` is empty,
      `labels` is empty. At most one row per cluster (enforced by a
      partial unique index in the migration).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @roles ~w(customer shared_warm)

  schema "runner_pools" do
    field :name, :string
    field :role, :string, default: "customer"
    field :owner, :string, default: ""
    field :labels, {:array, :string}, default: []
    field :min_warm, :integer, default: 0
    field :runner_group_id, :integer
    field :allowed_repos, {:array, :string}
    field :image, :string
    field :fleet_selector, :string
    field :pod_cpu_milli, :integer
    field :pod_memory_mb, :integer

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for inserting / updating a Pool row. Validates role
  semantics: customer pools must carry an `account_id` + `owner` +
  at least one label (the last entry being the dispatch label);
  shared_warm pools must leave those empty.
  """
  def changeset(pool \\ %__MODULE__{}, attrs) do
    pool
    |> cast(attrs, [
      :account_id,
      :name,
      :role,
      :owner,
      :labels,
      :min_warm,
      :runner_group_id,
      :allowed_repos,
      :image,
      :fleet_selector,
      :pod_cpu_milli,
      :pod_memory_mb
    ])
    |> validate_required([:name, :role])
    |> validate_inclusion(:role, @roles)
    |> validate_number(:min_warm, greater_than_or_equal_to: 0)
    |> validate_role_shape()
    |> unique_constraint(:name)
    |> unique_constraint(:role, name: :runner_pools_single_shared_warm)
    |> foreign_key_constraint(:account_id)
  end

  defp validate_role_shape(changeset) do
    case get_field(changeset, :role) do
      "customer" -> validate_customer_shape(changeset)
      "shared_warm" -> validate_shared_warm_shape(changeset)
      _ -> changeset
    end
  end

  defp validate_customer_shape(changeset) do
    changeset
    |> validate_required([:account_id, :owner])
    |> validate_labels_present()
  end

  defp validate_labels_present(changeset) do
    case get_field(changeset, :labels) do
      labels when is_list(labels) and labels != [] -> changeset
      _ -> add_error(changeset, :labels, "must contain at least one label (last is the dispatch label)")
    end
  end

  defp validate_shared_warm_shape(changeset) do
    changeset
    |> validate_change(:account_id, fn :account_id, value ->
      if is_nil(value), do: [], else: [account_id: "must be empty for shared_warm pools"]
    end)
    |> validate_change(:owner, fn :owner, value ->
      if value in [nil, ""], do: [], else: [owner: "must be empty for shared_warm pools"]
    end)
  end

  @doc """
  Returns the pool's *dispatch label* — the customer-scoped tag a
  workflow_job's `runs-on` must include. By convention the last
  entry of `labels`. SharedWarm pools have no dispatch label.
  """
  def dispatch_label(%__MODULE__{labels: labels}) when is_list(labels) and labels != [] do
    List.last(labels)
  end

  def dispatch_label(_), do: nil

  @doc """
  Atom form of the role for runtime matching. Stored as a string in
  the DB to keep the schema migration-friendly; callers prefer atoms.
  """
  def role_atom(%__MODULE__{role: "shared_warm"}), do: :shared_warm
  def role_atom(_), do: :customer
end
