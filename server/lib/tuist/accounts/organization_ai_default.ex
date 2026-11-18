defmodule Tuist.Accounts.OrganizationAIDefault do
  @moduledoc false
  use Ecto.Schema

  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.OrganizationAIModel

  schema "organization_ai_defaults" do
    belongs_to :organization, Organization
    belongs_to :model, OrganizationAIModel

    timestamps(type: :utc_datetime)
  end
end
