defmodule TuistCloud.Accounts.Account do
  @moduledoc ~S"""
  A module that represents the accounts table.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias TuistCloud.Projects.Project
  alias TuistCloud.Billing

  schema "accounts" do
    field :plan, Ecto.Enum, values: [none: 0, enterprise: 1, air: 2, pro: 3]
    field :name, :string
    field :user_id, :integer
    field :organization_id, :integer
    field :cache_upload_event_count, :integer
    field :cache_download_event_count, :integer
    field :customer_id, :string
    field :enterprise_plan_seats, :integer

    has_many(:projects, Project, on_delete: :delete_all)

    timestamps(inserted_at: :created_at)
  end

  def create_changeset(account, attrs) do
    changeset =
      account
      |> cast(attrs, [:name, :user_id, :organization_id, :customer_id, :plan])

    user_id = get_field(changeset, :user_id)

    changeset
    |> validate_required(
      [:name] ++
        if(Billing.enabled?(), do: [:customer_id], else: []) ++
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
    |> validate_change(:name, fn :name, name ->
      if String.contains?(name, ".") do
        [name: "can't contain a dot"]
      else
        []
      end
    end)
    |> validate_plan()
    |> update_change(:name, &String.downcase/1)
    |> unique_constraint(:name, name: "index_accounts_on_name")
    |> unique_constraint([:user_id])
    |> unique_constraint([:organization_id])
  end

  defp validate_plan(changeset) do
    changeset |> validate_inclusion(:plan, [:none, :enterprise, :air, :pro])
  end

  def update_changeset(account, attrs) do
    account
    |> cast(attrs, [:plan, :customer_id])
    |> validate_plan()
  end
end
