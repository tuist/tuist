defmodule Tuist.Automations.IssueLink do
  @moduledoc """
  A link between an automation alert firing on a test case and the
  GitHub issue Tuist opened for it.

  Written by the `create_github_issue` action and updated by the
  `issues.closed` webhook handler. The `(alert_id, test_case_id)` row
  with `state: :open` is the idempotency key — the action no-ops when
  one exists, so repeated fires of the same alert can't open duplicate
  issues.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Projects.Project
  alias Tuist.VCS.GitHubAppInstallation

  @states ~w(open resolved)

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "automation_issue_links" do
    field :test_case_id, Ecto.UUID
    field :github_repository_full_handle, :string
    field :github_issue_number, :integer
    field :github_issue_node_id, :string
    field :state, :string, default: "open"
    field :opened_at, :utc_datetime
    field :resolved_at, :utc_datetime

    belongs_to :project, Project, type: :integer
    belongs_to :alert, Alert
    belongs_to :github_app_installation, GitHubAppInstallation

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :project_id,
      :alert_id,
      :test_case_id,
      :github_app_installation_id,
      :github_repository_full_handle,
      :github_issue_number,
      :github_issue_node_id,
      :state,
      :opened_at
    ])
    |> validate_required([
      :project_id,
      :alert_id,
      :test_case_id,
      :github_repository_full_handle,
      :github_issue_number,
      :opened_at
    ])
    |> validate_inclusion(:state, @states)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:alert_id)
    |> foreign_key_constraint(:github_app_installation_id)
    |> unique_constraint([:alert_id, :test_case_id],
      name: :automation_issue_links_open_per_alert_test_case_index
    )
    |> unique_constraint(
      [:github_app_installation_id, :github_repository_full_handle, :github_issue_number],
      name: :automation_issue_links_installation_repo_issue_index
    )
  end

  def resolve_changeset(issue_link, resolved_at) do
    issue_link
    |> change(state: "resolved", resolved_at: resolved_at)
    |> validate_inclusion(:state, @states)
  end
end
