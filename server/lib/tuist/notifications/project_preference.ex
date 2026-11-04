defmodule Tuist.Notifications.ProjectPreference do
  @moduledoc """
  A user's override of their account choice for one project and notification
  kind. A missing row means the project follows its account.
  """
  use Ecto.Schema

  alias Tuist.Accounts.User
  alias Tuist.Projects.Project

  schema "notification_project_preferences" do
    belongs_to :user, User
    belongs_to :project, Project
    field :kind, :string
    field :enabled, :boolean

    timestamps(type: :utc_datetime)
  end
end
