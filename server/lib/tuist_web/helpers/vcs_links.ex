defmodule TuistWeb.Helpers.VCSLinks do
  @moduledoc """
  Helper functions for generating VCS (Version Control System) links.
  """

  use Phoenix.Component
  use Noora

  alias Tuist.VCS
  alias TuistWeb.Helpers.GitHubHost

  attr :project, :map, required: true
  attr :fallback, :string, default: nil
  attr :rest, :global

  def repository_link(assigns) do
    assigns = assign(assigns, :github_base_url, GitHubHost.base_url(assigns.project))

    ~H"""
    <%= if has_github_vcs?(@project) do %>
      <a
        href={"#{@github_base_url}/#{@project.vcs_connection.repository_full_handle}"}
        target="_blank"
        {@rest}
      >
        {@project.vcs_connection.repository_full_handle}
      </a>
    <% else %>
      <span :if={@fallback} {@rest}>{@fallback}</span>
    <% end %>
    """
  end

  attr :project, :map, required: true
  attr :commit_sha, :string, required: true
  attr :fallback, :string, default: nil
  attr :rest, :global

  def commit_link(assigns) do
    assigns = assign(assigns, :github_base_url, GitHubHost.base_url(assigns.project))

    ~H"""
    <%= if @commit_sha not in [nil, ""] do %>
      <%= if has_github_vcs?(@project) do %>
        <a
          href={"#{@github_base_url}/#{@project.vcs_connection.repository_full_handle}/commit/#{@commit_sha}"}
          target="_blank"
          {@rest}
        >
          {String.slice(@commit_sha, 0, 12)}
        </a>
      <% else %>
        <span {@rest}>{String.slice(@commit_sha, 0, 12)}</span>
      <% end %>
    <% else %>
      <span :if={@fallback} {@rest}>{@fallback}</span>
    <% end %>
    """
  end

  attr :project, :map, required: true
  attr :branch, :string, required: true
  attr :show_icon, :boolean, default: false
  attr :fallback, :string, default: nil
  attr :rest, :global

  def branch_link(assigns) do
    assigns = assign(assigns, :github_base_url, GitHubHost.base_url(assigns.project))

    ~H"""
    <%= if @branch not in [nil, ""] do %>
      <%= if has_github_vcs?(@project) do %>
        <a
          href={"#{@github_base_url}/#{@project.vcs_connection.repository_full_handle}/tree/#{@branch}"}
          target="_blank"
          {@rest}
        >
          <.git_branch :if={@show_icon} />
          {@branch}
        </a>
      <% else %>
        <span {@rest}>
          <.git_branch :if={@show_icon} />
          {@branch}
        </span>
      <% end %>
    <% else %>
      <span :if={@fallback} {@rest}>{@fallback}</span>
    <% end %>
    """
  end

  @doc """
  Returns the URL of the pull request a `refs/pull/<number>/<suffix>` git ref
  points to in the project's connected GitHub repository, or `nil` when the ref
  is not a pull request ref or the project has no GitHub repository connected.
  """
  def pull_request_url(project, git_ref) do
    with true <- has_github_vcs?(project),
         pr_number when is_integer(pr_number) <- VCS.pull_request_number_from_git_ref(git_ref) do
      "#{GitHubHost.base_url(project)}/#{project.vcs_connection.repository_full_handle}/pull/#{pr_number}"
    else
      _ -> nil
    end
  end

  attr :project, :map, required: true
  attr :path, :string, required: true
  attr :commit_sha, :string, default: nil
  attr :branch, :string, default: nil
  attr :fallback_branch, :string, default: nil
  attr :rest, :global

  def source_file_link(assigns) do
    source_ref = assigns.commit_sha || assigns.branch || assigns.fallback_branch

    assigns =
      assigns
      |> assign(:github_base_url, GitHubHost.base_url(assigns.project))
      |> assign(:source_ref, source_ref)
      |> assign(:valid_source_ref, valid_repository_ref?(source_ref))

    ~H"""
    <%= if has_github_vcs?(@project) and valid_repository_path?(@path) and @valid_source_ref do %>
      <a
        href={"#{@github_base_url}/#{@project.vcs_connection.repository_full_handle}/blob/#{@source_ref}/#{@path}"}
        target="_blank"
        {@rest}
      >
        {@path}
      </a>
    <% else %>
      <span {@rest}>{@path}</span>
    <% end %>
    """
  end

  defp has_github_vcs?(%{vcs_connection: %{provider: :github}}), do: true
  defp has_github_vcs?(_project), do: false

  defp valid_repository_path?(path) do
    String.match?(path, ~r/^(?:[A-Za-z0-9][A-Za-z0-9_.-]*\/)*[A-Za-z0-9][A-Za-z0-9_.-]*$/)
  end

  defp valid_repository_ref?(source_ref) when is_binary(source_ref) do
    source_ref != "" and
      not String.contains?(source_ref, ["?", "#", "\\"]) and
      Enum.all?(String.split(source_ref, "/"), &(&1 not in ["", ".", ".."]))
  end

  defp valid_repository_ref?(_source_ref), do: false
end
