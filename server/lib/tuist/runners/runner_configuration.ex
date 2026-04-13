defmodule Tuist.Runners.RunnerConfiguration do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Runners.RunnerJob

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "runner_configurations" do
    field :enabled, :boolean, default: false
    field :provisioning_mode, Ecto.Enum, values: [:managed, :self_hosted], default: :managed
    field :orchard_controller_url, :string
    field :orchard_service_account_name, :string
    field :orchard_encrypted_service_account_token, :binary
    field :default_tart_image, :string
    field :max_concurrent_jobs, :integer, default: 5
    field :label_prefix, :string, default: "tuist-runner"

    belongs_to :account, Account, type: :integer

    has_many :runner_jobs, RunnerJob

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :account_id,
      :enabled,
      :provisioning_mode,
      :orchard_controller_url,
      :orchard_service_account_name,
      :orchard_encrypted_service_account_token,
      :default_tart_image,
      :max_concurrent_jobs,
      :label_prefix
    ])
    |> validate_required([:account_id, :default_tart_image])
    |> unique_constraint(:account_id)
    |> foreign_key_constraint(:account_id)
    |> validate_number(:max_concurrent_jobs, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_self_hosted_fields()
  end

  def update_changeset(configuration, attrs) do
    configuration
    |> cast(attrs, [
      :enabled,
      :provisioning_mode,
      :orchard_controller_url,
      :orchard_service_account_name,
      :orchard_encrypted_service_account_token,
      :default_tart_image,
      :max_concurrent_jobs,
      :label_prefix
    ])
    |> validate_number(:max_concurrent_jobs, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_self_hosted_fields()
  end

  defp validate_self_hosted_fields(changeset) do
    if get_field(changeset, :provisioning_mode) == :self_hosted do
      validate_required(changeset, [:orchard_controller_url, :orchard_service_account_name])
    else
      changeset
    end
  end
end
