defmodule Tuist.VCS do
  @moduledoc """
  A module that provides functions to interact with VCS repositories.
  """

  alias Tuist.VCS
  alias Tuist.GitHub
  alias Tuist.Repo
  alias Tuist.Projects
  alias Tuist.Environment
  alias Tuist.CommandEvents

  @reportable_commands ["test", "share"]

  def supported_vcs_hosts() do
    ["GitHub"]
  end

  def get_repository_from_repository_url(repository_url) do
    vcs_uri = repository_url |> URI.parse()
    host = vcs_uri |> Map.get(:host)

    if host == "github.com" do
      client = get_client_for_provider(:github)

      get_repository_full_handle_from_url(repository_url)
      |> client.get_repository()
    else
      {:error, :unsupported_vcs}
    end
  end

  def get_user_permission(%{
        user: user,
        repository: %VCS.Repositories.Repository{provider: provider, full_handle: full_handle}
      }) do
    user = Repo.preload(user, :oauth2_identities)

    github_identity =
      user.oauth2_identities
      |> Enum.find(&(&1.provider == provider))

    client = get_client_for_provider(provider)

    if is_nil(github_identity) do
      nil
    else
      with {:user, {:ok, %VCS.User{username: username}}} <-
             {:user,
              client.get_user_by_id(%{
                id: github_identity.id_in_provider,
                repository_full_handle: full_handle
              })},
           {:permission, {:ok, %VCS.Repositories.Permission{} = permission}} <-
             {:permission,
              client.get_user_permission(%{
                username: username,
                repository_full_handle: full_handle
              })} do
        {:ok, permission}
      else
        {:user, {:error, error_message}} ->
          {:error, "Could not fetch user: #{error_message}"}

        {:permission, {:error, error_message}} ->
          {:error, "Could not fetch user permission: #{error_message}"}
      end
    end
  end

  defp get_client_for_provider(:github) do
    GitHub.Client
  end

  defp get_repository_full_handle_from_url(repository_url) do
    Regex.replace(~r/^git@(.+):/, repository_url, "https://\\1/")
    |> URI.parse()
    |> Map.get(:path)
    |> String.replace_leading("/", "")
    |> String.replace_trailing("/", "")
    |> String.replace_trailing(".git", "")
  end

  @doc """
  Returns `true` if the repository, identified by the `repository_full_handle`, is connected to the given project.
  """
  def connected?(%{repository_full_handle: repository_full_handle, project: project}) do
    Environment.github_app_configured?() and
      not is_nil(project.vcs_repository_full_handle) and
      project.vcs_repository_full_handle == repository_full_handle
  end

  def post_vcs_pull_request_comment(%{
        git_ref: git_ref,
        git_remote_url_origin: git_remote_url_origin,
        git_commit_sha: git_commit_sha,
        command_name: command_name,
        project: project,
        preview_url: preview_url,
        preview_qr_code_url: preview_qr_code_url,
        command_run_url: command_run_url
      }) do
    repository_full_handle =
      if is_nil(git_remote_url_origin) do
        nil
      else
        get_repository_full_handle_from_url(git_remote_url_origin)
      end

    should_post_report =
      Enum.member?(@reportable_commands, command_name) and
        not is_nil(git_commit_sha) and
        not is_nil(git_ref) and
        not is_nil(repository_full_handle) and
        connected?(%{
          repository_full_handle: repository_full_handle,
          project: project
        }) and
        String.starts_with?(git_ref, "refs/pull/")

    if should_post_report do
      client = get_client_for_provider(:github)

      issue_id = get_issue_id_from_git_ref(git_ref)

      existing_comment =
        get_existing_vcs_comment_id(%{
          client: client,
          repository: repository_full_handle,
          issue_id: issue_id
        })

      vcs_comment_body =
        get_vcs_comment_body(%{
          git_ref: git_ref,
          git_remote_url_origin: Projects.get_repository_url(project),
          preview_url: preview_url,
          preview_qr_code_url: preview_qr_code_url,
          command_run_url: command_run_url,
          project: project
        })

      update_or_create_vcs_comment(%{
        vcs_comment_body: vcs_comment_body,
        repository: repository_full_handle,
        issue_id: issue_id,
        existing_comment: existing_comment,
        client: client
      })
    end
  end

  defp get_existing_vcs_comment_id(%{client: client, repository: repository, issue_id: issue_id}) do
    case client.get_comments(%{repository_full_handle: repository, issue_id: issue_id}) do
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
          repository_full_handle: repository,
          issue_id: issue_id,
          body: vcs_comment_body
        })

      true ->
        client.update_comment(%{
          repository_full_handle: repository,
          comment_id: existing_comment.id,
          body: vcs_comment_body
        })
    end
  end

  defp get_vcs_comment_body(%{
         git_ref: git_ref,
         git_remote_url_origin: git_remote_url_origin,
         preview_url: preview_url,
         preview_qr_code_url: preview_qr_code_url,
         command_run_url: command_run_url,
         project: project
       }) do
    preview_command_events =
      get_latest_command_events(
        %{
          name: "share",
          get_identifier: & &1.preview.display_name,
          git_ref: git_ref,
          project: project
        },
        filter: &(not is_nil(&1.preview))
      )

    test_command_events =
      get_latest_command_events(%{
        name: "test",
        get_identifier: & &1.command_arguments,
        git_ref: git_ref,
        project: project
      })

    previews_body =
      get_previews_body(%{
        preview_command_events: preview_command_events,
        git_remote_url_origin: git_remote_url_origin,
        preview_url: preview_url,
        preview_qr_code_url: preview_qr_code_url,
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

  defp get_issue_id_from_git_ref(git_ref) do
    [issue_id, _merge] = git_ref |> String.split("/") |> Enum.take(-2)
    issue_id
  end

  defp get_latest_command_events(
         %{
           get_identifier: get_identifier,
           name: name,
           git_ref: git_ref,
           project: project
         },
         opts \\ []
       ) do
    filter = Keyword.get(opts, :filter, fn _ -> true end)

    CommandEvents.get_command_events_by_name_git_ref_and_project(
      %{
        name: name,
        git_ref: git_ref,
        project: project
      },
      preload: [:preview]
    )
    |> Enum.filter(filter)
    |> Enum.reduce(%{}, fn command_event, acc ->
      identifier = get_identifier.(command_event)
      current_event = Map.get(acc, identifier)

      if current_event == nil or
           NaiveDateTime.compare(
             command_event.created_at,
             current_event.created_at
           ) ==
             :gt do
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
         preview_qr_code_url: preview_qr_code_url,
         project: project
       }) do
    if Enum.empty?(preview_command_events) do
      nil
    else
      contains_ipas =
        Enum.any?(preview_command_events, fn preview_command_event ->
          preview_command_event.preview.type == :ipa
        end)

      """

      #### Tuist Previews 📦

      | App | Commit |#{if contains_ipas, do: " Open on device |", else: ""}
      | - | - |#{if contains_ipas, do: " - |", else: ""}
      #{Enum.map(preview_command_events, fn preview_command_event ->
        git_commit_sha = preview_command_event.git_commit_sha
        preview_url = preview_url.(%{project: project, preview: preview_command_event.preview})
        qr_code_image = get_qr_code_image(%{project: project, preview: preview_command_event.preview, contains_ipas: contains_ipas, preview_qr_code_url: preview_qr_code_url})

        """
        | [#{preview_command_event.preview.display_name}](#{preview_url}) | [#{git_commit_sha |> String.slice(0, 9)}](#{git_remote_url_origin}/commit/#{git_commit_sha}) |#{qr_code_image}
        """
      end)}
      """
    end
  end

  defp get_qr_code_image(%{
         project: project,
         preview: preview,
         contains_ipas: contains_ipas,
         preview_qr_code_url: preview_qr_code_url
       }) do
    case preview.type do
      :app_bundle ->
        if contains_ipas, do: " |", else: ""

      :ipa ->
        " <img width=100px src=\"#{preview_qr_code_url.(%{project: project, preview: preview})}\" /> |"
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
