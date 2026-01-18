defmodule TuistWeb.Helpers.VCSLinks do
  @moduledoc """
  Helper functions for generating VCS (Version Control System) links.
  """

  use Phoenix.Component
  use Noora

  attr :project, :map, required: true
  attr :commit_sha, :string, required: true
  attr :fallback, :string, default: nil
  attr :rest, :global

  def commit_link(assigns) do
    ~H"""
    <%= if @commit_sha not in [nil, ""] do %>
      <%= if has_github_vcs?(@project) do %>
        <a
          href={"https://github.com/#{@project.vcs_connection.repository_full_handle}/commit/#{@commit_sha}"}
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
    ~H"""
    <%= if @branch not in [nil, ""] do %>
      <%= if has_github_vcs?(@project) do %>
        <a
          href={"https://github.com/#{@project.vcs_connection.repository_full_handle}/tree/#{@branch}"}
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

  defp has_github_vcs?(project) do
    project.vcs_connection && project.vcs_connection.provider == :github
  end
end
