defmodule TuistWeb.Runs.PullRequestButton do
  @moduledoc """
  Header button linking a test or build run to the pull request it ran for.
  """
  use TuistWeb, :html
  use Noora

  alias Tuist.VCS
  alias TuistWeb.Helpers.VCSLinks

  attr :project, :map, required: true
  attr :git_ref, :string, required: true
  attr :disabled, :boolean, default: false

  def pull_request_button(assigns) do
    assigns =
      assigns
      |> assign(:url, VCSLinks.pull_request_url(assigns.project, assigns.git_ref))
      |> assign(:number, VCS.pull_request_number_from_git_ref(assigns.git_ref))

    ~H"""
    <.button
      :if={@url}
      href={@url}
      label={dgettext("dashboard", "PR #%{number}", number: @number)}
      variant="secondary"
      size="medium"
      target="_blank"
      disabled={@disabled}
      data-part="pull-request-button"
    >
      <:icon_left><.git_merge /></:icon_left>
    </.button>
    """
  end
end
