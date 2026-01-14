defmodule TuistWeb.Helpers.FailureMessage do
  @moduledoc """
  Helper functions for formatting test case failure messages.
  """

  use TuistWeb, :verified_routes
  use Gettext, backend: TuistWeb.Gettext

  import Phoenix.HTML, only: [raw: 1]

  @doc """
  Formats a failure message with optional linking to source code in GitHub.
  """
  def format_failure_message(failure, run) do
    path = if failure.path in [nil, ""], do: nil, else: failure.path

    message =
      case {path, failure.issue_type, failure.message} do
        # No path cases
        {nil, "assertion_failure", nil} ->
          dgettext("dashboard_tests", "Expectation failed")

        {nil, "assertion_failure", message} ->
          dgettext("dashboard_tests", "Expectation failed: %{message}", message: message)

        {nil, "error_thrown", nil} ->
          dgettext("dashboard_tests", "Caught error")

        {nil, "error_thrown", message} ->
          dgettext("dashboard_tests", "Caught error: %{message}", message: message)

        {nil, "issue_recorded", nil} ->
          dgettext("dashboard_tests", "Issue recorded")

        {nil, "issue_recorded", message} ->
          dgettext("dashboard_tests", "Issue recorded: %{message}", message: message)

        {nil, _, nil} ->
          dgettext("dashboard_tests", "Unknown error")

        {nil, _, message} ->
          message

        # Has path cases
        {path, "assertion_failure", nil} ->
          dgettext("dashboard_tests", "Expectation failed at %{location}", location: "#{path}:#{failure.line_number}")

        {path, "assertion_failure", message} ->
          dgettext("dashboard_tests", "Expectation failed at %{location}: %{message}",
            location: "#{path}:#{failure.line_number}",
            message: message
          )

        {path, "error_thrown", nil} ->
          dgettext("dashboard_tests", "Caught error at %{location}", location: "#{path}:#{failure.line_number}")

        {path, "error_thrown", message} ->
          dgettext("dashboard_tests", "Caught error at %{location}: %{message}",
            location: "#{path}:#{failure.line_number}",
            message: message
          )

        {path, "issue_recorded", nil} ->
          dgettext("dashboard_tests", "Issue recorded at %{location}", location: "#{path}:#{failure.line_number}")

        {path, "issue_recorded", message} ->
          dgettext("dashboard_tests", "Issue recorded at %{location}: %{message}",
            location: "#{path}:#{failure.line_number}",
            message: message
          )

        {path, _, nil} ->
          "#{path}:#{failure.line_number}"

        {path, _, message} ->
          "#{path}:#{failure.line_number}: #{message}"
      end

    linkify_failure_location(message, path, failure, run)
  end

  defp linkify_failure_location(message, path, failure, run) do
    if not is_nil(path) and has_github_vcs?(run) do
      location_text = "#{path}:#{failure.line_number}"

      location_link =
        ~s(<a href="https://github.com/#{run.project.vcs_connection.repository_full_handle}/blob/#{run.git_commit_sha}/#{path}#L#{failure.line_number}" target="_blank">#{location_text}</a>)

      message
      |> String.replace(location_text, location_link)
      |> raw()
    else
      message
    end
  end

  defp has_github_vcs?(run) do
    case run do
      %{project: %{vcs_connection: %{provider: :github}}, git_commit_sha: sha} when not is_nil(sha) ->
        true

      _ ->
        false
    end
  end
end
