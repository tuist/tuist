defmodule Tuist.Accounts.Account do
  @moduledoc ~S"""
  A module that represents the accounts table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User
  alias Tuist.Billing.Subscription
  alias Tuist.GitHubAppInstallations.GitHubAppInstallation
  alias Tuist.Projects.Project

  @derive {
    Flop.Schema,
    filterable: [:customer_id, :current_month_remote_cache_hits_count_updated_at], sortable: [:name]
  }

  schema "accounts" do
    field :name, :string
    field :billing_email, :string
    field :customer_id, :string
    field :current_month_remote_cache_hits_count, :integer
    field :current_month_remote_cache_hits_count_updated_at, :naive_datetime
    field :namespace_tenant_id, :string

    belongs_to :organization, Organization
    belongs_to :user, User

    has_many(:projects, Project, on_delete: :delete_all)
    has_many(:subscriptions, Subscription, on_delete: :delete_all)
    has_one(:github_app_installation, GitHubAppInstallation, on_delete: :delete_all)

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(inserted_at: :created_at)
  end

  def update_customer_id_changeset(account, attrs) do
    account
    |> cast(attrs, [
      :customer_id
    ])
    |> validate_required([:customer_id])
  end

  def create_changeset(account, attrs) do
    changeset =
      cast(account, attrs, [
        :name,
        :billing_email,
        :user_id,
        :organization_id,
        :customer_id,
        :current_month_remote_cache_hits_count,
        :current_month_remote_cache_hits_count_updated_at
      ])

    user_id = get_field(changeset, :user_id)

    changeset
    |> validate_required(
      [:name, :billing_email] ++
        if(is_nil(user_id), do: [:organization_id], else: [:user_id])
    )
    |> validate_change(:organization_id, fn :organization_id, organization_id ->
      if not is_nil(user_id) and not is_nil(organization_id) do
        [
          organization_id: "only one of user_id or organization_id can be present",
          user_id: "only one of user_id or organization_id can be present"
        ]
      else
        []
      end
    end)
    |> validate_handle()
    |> unique_constraint([:user_id])
    |> unique_constraint([:organization_id])
  end

  def billing_changeset(account, attrs) do
    cast(account, attrs, [
      :customer_id,
      :current_month_remote_cache_hits_count,
      :current_month_remote_cache_hits_count_updated_at
    ])
  end

  def update_changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :namespace_tenant_id])
    |> validate_handle()
    |> unique_constraint(:namespace_tenant_id)
  end

  defp validate_handle(changeset) do
    changeset
    |> validate_format(:name, ~r/^[a-zA-Z0-9-]+$/, message: "must contain only alphanumeric characters")
    |> validate_length(:name, min: 1, max: 32)
    |> validate_exclusion(:name, Application.get_env(:tuist, :blocked_handles))
    |> unique_constraint(:name, name: "index_accounts_on_name")
  end
end
