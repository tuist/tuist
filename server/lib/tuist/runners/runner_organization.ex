defmodule Tuist.Runners.RunnerOrganization do
  @moduledoc """
  Represents customer organization settings for Tuist Runners.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "runner_organizations" do
    field :enabled, :boolean, default: false
    field :label_prefix, :string
    field :allowed_labels, {:array, :string}
    field :max_concurrent_jobs, :integer
    field :github_app_installation_id, :integer

    belongs_to :account, Tuist.Accounts.Account
    has_many :jobs, Tuist.Runners.RunnerJob, foreign_key: :organization_id

    timestamps(type: :utc_datetime)
  end

  def changeset(runner_organization, attrs) do
    runner_organization
    |> cast(attrs, [
      :id,
      :account_id,
      :enabled,
      :label_prefix,
      :allowed_labels,
      :max_concurrent_jobs,
      :github_app_installation_id
    ])
    |> validate_required([
      :id,
      :account_id
    ])
    |> validate_number(:max_concurrent_jobs, greater_than: 0)
    |> validate_number(:github_app_installation_id, greater_than: 0)
    |> validate_format(:label_prefix, ~r/^[a-z0-9-]+$/)
    |> unique_constraint(:account_id)
    |> unique_constraint(:github_app_installation_id)
    |> foreign_key_constraint(:account_id)
  end

  def enabled_query do
    from org in __MODULE__, where: org.enabled == true
  end

  def by_account_id_query(account_id) do
    from org in __MODULE__, where: org.account_id == ^account_id
  end

  def by_github_installation_id_query(installation_id) do
    from org in __MODULE__, where: org.github_app_installation_id == ^installation_id
  end

  def with_labels_query(labels) do
    from org in enabled_query(),
      where: fragment("? && ?", org.allowed_labels, ^labels)
  end
end
