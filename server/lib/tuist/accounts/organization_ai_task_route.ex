defmodule Tuist.Accounts.OrganizationAITaskRoute do
  @moduledoc """
  Sends one application task to a configured model instead of the
  organization's default. Each task belongs to a category for display.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.OrganizationAIModel

  @tasks [pulse_grouping: :pulse, pulse_explanation: :pulse]

  schema "organization_ai_task_routes" do
    belongs_to :organization, Organization
    belongs_to :model, OrganizationAIModel
    field :task, Ecto.Enum, values: Keyword.keys(@tasks)

    timestamps(type: :utc_datetime)
  end

  @doc "Routable tasks and their categories, in display order."
  def tasks, do: @tasks

  def changeset(route, attrs) do
    route
    |> cast(attrs, [:task, :model_id])
    |> validate_required([:organization_id, :task, :model_id])
    |> validate_number(:model_id, greater_than: 0, less_than_or_equal_to: 9_223_372_036_854_775_807)
    |> unique_constraint([:organization_id, :task])
  end
end
