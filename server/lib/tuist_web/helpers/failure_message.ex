defmodule TuistWeb.Helpers.FailureMessage do
  @moduledoc """
  Helper functions for formatting test case failure messages.
  """

  use TuistWeb, :verified_routes
  use Gettext, backend: TuistWeb.Gettext

  import Phoenix.HTML, only: [raw: 1]

  alias Tuist.VCS

  @doc """
  Formats a failure message with optional linking to source code in GitHub.
  """
  def format_failure_message(failure, run) do
    path = if failure.path in [nil, ""], do: nil, else: failure.path
    message = build_failure_message(path, failure.issue_type, failure.message, failure.line_number)
    linkify_failure_location(message, path, failure, run)
  end

  defp build_failure_message(nil, issue_type, message, _line_number) do
    format_message_without_path(issue_type, message)
  end

  defp build_failure_message(path, issue_type, message, line_number) do
    format_message_with_path(issue_type, message, path, line_number)
  end

  defp format_message_without_path("assertion_failure", nil), do: dgettext("dashboard_tests", "Expectation failed")

  defp format_message_without_path("assertion_failure", message),
    do: dgettext("dashboard_tests", "Expectation failed: %{message}", message: message)

  defp format_message_without_path("error_thrown", nil), do: dgettext("dashboard_tests", "Caught error")

  defp format_message_without_path("error_thrown", message),
    do: dgettext("dashboard_tests", "Caught error: %{message}", message: message)

  defp format_message_without_path("issue_recorded", nil), do: dgettext("dashboard_tests", "Issue recorded")

  defp format_message_without_path("issue_recorded", message),
    do: dgettext("dashboard_tests", "Issue recorded: %{message}", message: message)

  defp format_message_without_path(_, nil), do: dgettext("dashboard_tests", "Unknown error")

  defp format_message_without_path(_, message), do: message

  defp format_message_with_path("assertion_failure", nil, path, line_number),
    do: dgettext("dashboard_tests", "Expectation failed at %{location}", location: "#{path}:#{line_number}")

  defp format_message_with_path("assertion_failure", message, path, line_number) do
    dgettext("dashboard_tests", "Expectation failed at %{location}: %{message}",
      location: "#{path}:#{line_number}",
      message: message
    )
  end

  defp format_message_with_path("error_thrown", nil, path, line_number),
    do: dgettext("dashboard_tests", "Caught error at %{location}", location: "#{path}:#{line_number}")

  defp format_message_with_path("error_thrown", message, path, line_number) do
    dgettext("dashboard_tests", "Caught error at %{location}: %{message}",
      location: "#{path}:#{line_number}",
      message: message
    )
  end

  defp format_message_with_path("issue_recorded", nil, path, line_number),
    do: dgettext("dashboard_tests", "Issue recorded at %{location}", location: "#{path}:#{line_number}")

  defp format_message_with_path("issue_recorded", message, path, line_number) do
    dgettext("dashboard_tests", "Issue recorded at %{location}: %{message}",
      location: "#{path}:#{line_number}",
      message: message
    )
  end

  defp format_message_with_path(_, nil, path, line_number), do: "#{path}:#{line_number}"
  defp format_message_with_path(_, message, path, line_number), do: "#{path}:#{line_number}: #{message}"

  defp linkify_failure_location(message, path, failure, run) do
    if not is_nil(path) and has_github_vcs?(run) do
      location_text = "#{path}:#{failure.line_number}"
      base_url = github_base_url(run)

      location_link =
        ~s(<a href="#{base_url}/#{run.project.vcs_connection.repository_full_handle}/blob/#{run.git_commit_sha}/#{path}#L#{failure.line_number}" target="_blank">#{location_text}</a>)

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

  defp github_base_url(run) do
    run
    |> resolve_github_app_installation()
    |> case do
      %{client_url: client_url} when is_binary(client_url) and client_url != "" -> client_url
      _ -> VCS.default_client_url()
    end
  end

  defp resolve_github_app_installation(%{
         project: %{vcs_connection: %{github_app_installation: %{client_url: _} = installation}}
       }), do: installation

  defp resolve_github_app_installation(%{project: %{vcs_connection: %Tuist.Projects.VCSConnection{} = vcs_connection}}) do
    %{github_app_installation: installation} =
      Tuist.Repo.preload(vcs_connection, :github_app_installation)

    installation
  end

  defp resolve_github_app_installation(_), do: nil
end
