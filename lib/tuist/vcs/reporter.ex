defmodule Tuist.VCS.Reporter do
  @moduledoc """
  A module that implements that sends Tuist reports to the appropriate VCS, such as GitHub.
  """
  alias Tuist.Environment
  alias Tuist.CommandEvents

  @reportable_commands ["test", "share"]

  def post_vcs_pull_request_comment(%{
        git_ref: git_ref,
        git_remote_url_origin: git_remote_url_origin,
        git_commit_sha: git_commit_sha,
        command_name: command_name,
        project: project,
        preview_url: preview_url,
        command_run_url: command_run_url
      }) do
    should_post_report =
      Environment.github_app_configured?() and
        Enum.member?(@reportable_commands, command_name) and
        not is_nil(git_commit_sha) and
        not is_nil(git_ref) and
        not is_nil(git_remote_url_origin) and
        String.starts_with?(git_ref, "refs/pull/")

    if should_post_report do
      client = Tuist.GitHub.Client

      repository = get_repository_from_remote_url_origin(git_remote_url_origin)

      issue_id = get_issue_id_from_git_ref(git_ref)

      existing_comment =
        get_existing_vcs_comment_id(%{client: client, repository: repository, issue_id: issue_id})

      vcs_comment_body =
        get_vcs_comment_body(%{
          git_ref: git_ref,
          git_remote_url_origin: git_remote_url_origin,
          preview_url: preview_url,
          command_run_url: command_run_url,
          project: project
        })

      update_or_create_vcs_comment(%{
        vcs_comment_body: vcs_comment_body,
        repository: repository,
        issue_id: issue_id,
        existing_comment: existing_comment,
        client: client
      })
    end
  end

  defp get_existing_vcs_comment_id(%{client: client, repository: repository, issue_id: issue_id}) do
    case client.get_comments(%{repository: repository, issue_id: issue_id}) do
      {:ok, comments} ->
        comments
        |> Enum.find(&(&1.client_id == Environment.github_app_client_id()))

      _ ->
        nil
    end
  end

  defp update_or_create_vcs_comment(%{
         vcs_comment_body: vcs_comment_body,
         repository: repository,
         issue_id: issue_id,
         existing_comment: existing_comment,
         client: client
       }) do
    cond do
      is_nil(vcs_comment_body) ->
        :ok

      is_nil(existing_comment) ->
        client.create_comment(%{
          repository: repository,
          issue_id: issue_id,
          body: vcs_comment_body
        })

      true ->
        client.update_comment(%{
          repository: repository,
          comment_id: existing_comment.id,
          body: vcs_comment_body
        })
    end
  end

  defp get_vcs_comment_body(%{
         git_ref: git_ref,
         git_remote_url_origin: git_remote_url_origin,
         preview_url: preview_url,
         command_run_url: command_run_url,
         project: project
       }) do
    preview_command_events =
      get_latest_command_events(
        %{
          name: "share",
          get_identifier: & &1.preview.display_name,
          git_ref: git_ref,
          git_remote_url_origin: git_remote_url_origin
        },
        filter: &(not is_nil(&1.preview))
      )

    test_command_events =
      get_latest_command_events(%{
        name: "test",
        get_identifier: & &1.command_arguments,
        git_ref: git_ref,
        git_remote_url_origin: git_remote_url_origin
      })

    previews_body =
      get_previews_body(%{
        preview_command_events: preview_command_events,
        git_remote_url_origin: git_remote_url_origin,
        preview_url: preview_url,
        project: project
      })

    test_body =
      get_test_body(%{
        test_command_events: test_command_events,
        git_remote_url_origin: git_remote_url_origin,
        command_run_url: command_run_url,
        project: project
      })

    if is_nil(previews_body) and is_nil(test_body) do
      nil
    else
      """
      ### 🛠️ Tuist Run Report 🛠️
      """ <>
        (previews_body || "") <>
        (test_body || "")
    end
  end

  defp get_repository_from_remote_url_origin(git_remote_url_origin) do
    git_remote_url_origin |> URI.parse() |> Map.get(:path) |> String.replace_leading("/", "")
  end

  defp get_issue_id_from_git_ref(git_ref) do
    [issue_id, _merge] = git_ref |> String.split("/") |> Enum.take(-2)
    issue_id
  end

  defp get_latest_command_events(
         %{
           get_identifier: get_identifier,
           name: name,
           git_ref: git_ref,
           git_remote_url_origin: git_remote_url_origin
         },
         opts \\ []
       ) do
    filter = Keyword.get(opts, :filter, fn _ -> true end)

    CommandEvents.get_command_events_by_name_git_ref_and_remote(
      %{
        name: name,
        git_ref: git_ref,
        git_remote_url_origin: git_remote_url_origin
      },
      preload: [:preview]
    )
    |> Enum.filter(filter)
    |> Enum.reduce(%{}, fn command_event, acc ->
      identifier = get_identifier.(command_event)
      current_event = Map.get(acc, identifier)

      if current_event == nil or
           Date.compare(command_event.created_at, current_event.created_at) == :gt do
        Map.put(acc, identifier, command_event)
      else
        acc
      end
    end)
    |> Map.values()
  end

  defp get_previews_body(%{
         preview_command_events: preview_command_events,
         git_remote_url_origin: git_remote_url_origin,
         preview_url: preview_url,
         project: project
       }) do
    if Enum.empty?(preview_command_events) do
      nil
    else
      """

      #### Tuist Previews 📦

      | App | Commit |
      | - | - |
      #{Enum.map(preview_command_events, fn preview_command_event ->
        git_commit_sha = preview_command_event.git_commit_sha
        preview_url = preview_url.(%{project: project, preview: preview_command_event.preview})

        """
        | [#{preview_command_event.preview.display_name}](#{preview_url}) | [#{git_commit_sha |> String.slice(0, 9)}](#{git_remote_url_origin}/commit/#{git_commit_sha}) |
        """
      end)}
      """
    end
  end

  defp get_test_body(%{
         test_command_events: test_command_events,
         git_remote_url_origin: git_remote_url_origin,
         command_run_url: command_run_url,
         project: project
       }) do
    if Enum.empty?(test_command_events) do
      nil
    else
      """

      #### Tuist Tests 🧪

      | Command | Status | Cache hit rate | Tests | Skipped | Ran | Commit |
      |:-:|:-:|:-:|:-:|:-:|:-:|:-:|
      #{Enum.map(test_command_events, fn test_command_event ->
        git_commit_sha = test_command_event.git_commit_sha
        total_number_of_tests = test_command_event.test_targets |> Enum.count()
        tests_skipped = (test_command_event.local_test_target_hits |> Enum.count()) + (test_command_event.remote_test_target_hits |> Enum.count())
        test_url = command_run_url.(%{project: project, command_event: test_command_event})

        """
        | [#{test_command_event.command_arguments}](#{test_url}) | #{get_status_text(test_command_event)} | #{get_cache_hit_rate(test_command_event)} | #{total_number_of_tests} | #{tests_skipped} | #{total_number_of_tests - tests_skipped} | [#{git_commit_sha |> String.slice(0, 9)}](#{git_remote_url_origin}/commit/#{git_commit_sha}) |
        """
      end)}
      """
    end
  end

  defp get_cache_hit_rate(command_event) do
    total_targets = command_event.cacheable_targets |> Enum.count()

    total_hits =
      (command_event.local_cache_target_hits |> Enum.count()) +
        (command_event.remote_cache_target_hits |> Enum.count())

    if total_targets == 0 do
      "0 %"
    else
      "#{(total_hits / total_targets * 100) |> Float.floor() |> round()} %"
    end
  end

  defp get_status_text(command_event) do
    case command_event.status do
      :failure -> "❌"
      :success -> "✅"
    end
  end
end
