defmodule Tuist.Accounts.Account do
  @moduledoc ~S"""
  A module that represents the accounts table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User
  alias Tuist.Billing.Subscription
  alias Tuist.Projects.Project
  alias Tuist.Slack.Installation, as: SlackInstallation
  alias Tuist.Vault.Binary
  alias Tuist.VCS.GitHubAppInstallation

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
    field :region, Ecto.Enum, values: [all: 0, europe: 1, usa: 2], default: :all

    field :s3_bucket_name, :string
    field :s3_access_key_id, Binary
    field :s3_secret_access_key, Binary
    field :s3_region, :string
    field :s3_endpoint, :string

    belongs_to :organization, Organization
    belongs_to :user, User

    has_many(:projects, Project, on_delete: :delete_all)
    has_many(:subscriptions, Subscription, on_delete: :delete_all)
    has_many(:cache_endpoints, AccountCacheEndpoint, on_delete: :delete_all)
    has_one(:github_app_installation, GitHubAppInstallation, on_delete: :delete_all)
    has_one(:slack_installation, SlackInstallation, on_delete: :delete_all)

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
    |> cast(attrs, [:name, :namespace_tenant_id, :region, :billing_email])
    |> validate_handle()
    |> validate_inclusion(:region, [:all, :europe, :usa])
    |> unique_constraint(:namespace_tenant_id)
  end

  @s3_fields [:s3_bucket_name, :s3_access_key_id, :s3_secret_access_key, :s3_region, :s3_endpoint]

  def s3_storage_changeset(account, attrs) do
    account
    |> cast(attrs, @s3_fields)
    |> validate_s3_configuration()
  end

  defp validate_s3_configuration(changeset) do
    bucket_name = get_field(changeset, :s3_bucket_name)
    access_key_id = get_field(changeset, :s3_access_key_id)
    secret_access_key = get_field(changeset, :s3_secret_access_key)

    has_any_s3_field? =
      Enum.any?([bucket_name, access_key_id, secret_access_key], &(not is_nil(&1)))

    if has_any_s3_field? do
      changeset
      |> validate_required([:s3_bucket_name, :s3_access_key_id, :s3_secret_access_key],
        message: "is required when configuring custom S3 storage"
      )
      |> validate_length(:s3_bucket_name, min: 3, max: 63)
      |> validate_format(:s3_bucket_name, ~r/^[a-z0-9][a-z0-9.-]*[a-z0-9]$/,
        message: "must be a valid S3 bucket name (lowercase letters, numbers, hyphens, and periods)"
      )
      |> validate_s3_endpoint()
    else
      changeset
    end
  end

  defp validate_s3_endpoint(changeset) do
    case get_field(changeset, :s3_endpoint) do
      nil ->
        changeset

      endpoint ->
        case URI.parse(endpoint) do
          %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
            changeset

          _ ->
            add_error(changeset, :s3_endpoint, "must be a valid URL with http or https scheme")
        end
    end
  end

  defp validate_handle(changeset) do
    changeset
    |> validate_format(:name, ~r/^[a-zA-Z0-9-]+$/, message: "must contain only alphanumeric characters")
    |> validate_length(:name, min: 1, max: 32)
    |> validate_exclusion(:name, Application.get_env(:tuist, :blocked_handles))
    |> unique_constraint(:name, name: "index_accounts_on_name")
  end
end
