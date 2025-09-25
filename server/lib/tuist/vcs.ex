defmodule Tuist.VCS do
  @moduledoc """
  A module that provides functions to interact with VCS repositories.
  """

  use Gettext, backend: TuistWeb.Gettext

  import Ecto.Query

  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.Preview
  alias Tuist.Bundles
  alias Tuist.Bundles.Bundle
  alias Tuist.CommandEvents
  alias Tuist.Environment
  alias Tuist.GitHub
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Runs
  alias Tuist.Utilities.DateFormatter
  alias Tuist.VCS

  @tuist_run_report_prefix "### 🛠️ Tuist Run Report 🛠️"

  def supported_vcs_hosts do
    ["GitHub"]
  end

  def get_repository_content(
        %{repository_full_handle: repository_full_handle, provider: provider, token: token},
        opts \\ []
      ) do
    client = get_client_for_provider(provider)

    client.get_repository_content(
      %{
        repository_full_handle: repository_full_handle,
        token: token
      },
      opts
    )
  end

  def get_tags(%{provider: provider, repository_full_handle: repository_full_handle, token: token}) do
    client = get_client_for_provider(provider)

    client.get_tags(%{repository_full_handle: repository_full_handle, token: token})
  end

  def get_source_archive_by_tag_and_repository_full_handle(%{
        provider: provider,
        repository_full_handle: repository_full_handle,
        tag: tag,
        token: token
      }) do
    client = get_client_for_provider(provider)

    client.get_source_archive_by_tag_and_repository_full_handle(%{
      repository_full_handle: repository_full_handle,
      tag: tag,
      token: token
    })
  end

  def get_repository_from_repository_url(repository_url) do
    case get_provider_from_repository_url(repository_url) do
      {:ok, provider} ->
        client = get_client_for_provider(provider)

        repository_url
        |> get_repository_full_handle_from_url()
        |> elem(1)
        |> client.get_repository()

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_provider_from_repository_url(repository_url) do
    vcs_uri = URI.parse(repository_url)
    host = Map.get(vcs_uri, :host)

    case host do
      "github.com" -> {:ok, :github}
      _ -> {:error, :unsupported_vcs}
    end
  end

  def get_user_permission(%{
        user: user,
        repository: %VCS.Repositories.Repository{provider: provider, full_handle: full_handle}
      }) do
    user = Repo.preload(user, :oauth2_identities)

    github_identity = Enum.find(user.oauth2_identities, &(&1.provider == provider))

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

  def get_repository_full_handle_from_url(repository_url) do
    full_handle =
      ~r/^git@(.+):/
      |> Regex.replace(repository_url, "https://\\1/")
      |> URI.parse()
      |> Map.get(:path)
      |> String.replace_leading("/", "")
      |> String.replace_trailing("/", "")
      |> String.replace_trailing(".git", "")

    if full_handle |> String.split("/") |> Enum.count() == 2 do
      {:ok, full_handle}
    else
      {:error, :invalid_repository_url}
    end
  end

  @doc """
  Returns `true` if the repository, identified by the `repository_full_handle`, is connected to the given project.
  """
  def connected?(%{repository_full_handle: repository_full_handle, project: project}) do
    Environment.github_app_configured?() and
      not is_nil(project.vcs_repository_full_handle) and
      String.downcase(project.vcs_repository_full_handle) ==
        String.downcase(repository_full_handle)
  end

  def enqueue_vcs_pull_request_comment(args) do
    args
    |> VCS.Workers.CommentWorker.new()
    |> Oban.insert()
  end

  @doc """
  Creates a comment on a VCS issue/pull request.
  """
  def create_comment(%{repository_full_handle: repository_full_handle, git_ref: git_ref, body: body, project: project}) do
    cond do
      not String.starts_with?(git_ref, "refs/pull/") ->
        {:error, :not_pull_request}

      not connected?(%{repository_full_handle: repository_full_handle, project: project}) ->
        {:error, :repository_not_connected}

      true ->
        client = get_client_for_provider(:github)
        issue_id = get_issue_id_from_git_ref(git_ref)

        client.create_comment(%{
          repository_full_handle: repository_full_handle,
          issue_id: issue_id,
          body: body
        })
    end
  end

  @doc """
  Updates an existing comment on a VCS issue/pull request.
  """
  def update_comment(%{
        repository_full_handle: repository_full_handle,
        comment_id: comment_id,
        body: body,
        project: project
      }) do
    if connected?(%{repository_full_handle: repository_full_handle, project: project}) do
      client = get_client_for_provider(:github)

      client.update_comment(%{
        repository_full_handle: repository_full_handle,
        comment_id: comment_id,
        body: body
      })
    else
      {:error, :repository_not_connected}
    end
  end

  def post_vcs_pull_request_comment(%{
        git_ref: git_ref,
        git_remote_url_origin: git_remote_url_origin,
        git_commit_sha: git_commit_sha,
        project: project,
        preview_url: preview_url,
        preview_qr_code_url: preview_qr_code_url,
        command_run_url: command_run_url,
        bundle_url: bundle_url,
        build_url: build_url
      }) do
    repository_full_handle =
      if is_nil(git_remote_url_origin) do
        nil
      else
        git_remote_url_origin |> get_repository_full_handle_from_url() |> elem(1)
      end

    should_post_report =
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

      vcs_comment_body =
        get_vcs_comment_body(%{
          git_ref: git_ref,
          git_remote_url_origin: Projects.get_repository_url(project),
          preview_url: preview_url,
          preview_qr_code_url: preview_qr_code_url,
          command_run_url: command_run_url,
          build_url: build_url,
          bundle_url: bundle_url,
          project: project
        })

      existing_comment =
        get_existing_vcs_comment_id(%{
          client: client,
          repository: repository_full_handle,
          issue_id: issue_id
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
        Enum.find(comments, fn comment ->
          comment.client_id == Environment.github_app_client_id() and
            String.starts_with?(comment.body, @tuist_run_report_prefix)
        end)

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
         build_url: build_url,
         bundle_url: bundle_url,
         project: project
       }) do
    previews =
      latest_previews(%{
        git_ref: git_ref,
        project: project
      })

    test_command_events =
      get_latest_command_events(%{
        name: "test",
        get_identifier: & &1.command_arguments,
        git_ref: git_ref,
        project: project
      })

    builds =
      get_latest_builds(%{
        git_ref: git_ref,
        project: project
      })

    previews_body =
      get_previews_body(%{
        previews: previews,
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

    bundles_body =
      bundles_body(%{
        project: project,
        git_ref: git_ref,
        git_remote_url_origin: git_remote_url_origin,
        bundle_url: bundle_url
      })

    builds_body =
      get_builds_body(%{
        builds: builds,
        git_remote_url_origin: git_remote_url_origin,
        build_url: build_url,
        project: project
      })

    if is_nil(previews_body) and is_nil(test_body) and is_nil(bundles_body) and
         is_nil(builds_body) do
      nil
    else
      """
      #{@tuist_run_report_prefix}
      """ <>
        (previews_body || "") <> (test_body || "") <> (builds_body || "") <> (bundles_body || "")
    end
  end

  defp bundles_body(%{
         project: project,
         git_ref: git_ref,
         git_remote_url_origin: git_remote_url_origin,
         bundle_url: bundle_url
       }) do
    bundles =
      from(b in Bundle)
      |> where([b], b.project_id == ^project.id and b.git_ref == ^git_ref)
      |> order_by([b], desc: b.inserted_at)
      |> distinct([b], b.name)
      |> Repo.all()

    if Enum.empty?(bundles) do
      nil
    else
      """

      #### Bundles 🧰

      | Bundle | Commit | Install size | Download size |
      | - | - | - | - |
      #{Enum.map(bundles, fn bundle ->
        {install_size_deviation, download_size_deviation} = project_bundle_size_deviations(project, bundle)
        """
        | [#{bundle.name}](#{bundle_url.(%{project: project, bundle: bundle})}) | [#{String.slice(bundle.git_commit_sha, 0, 9)}](#{git_remote_url_origin}/commit/#{bundle.git_commit_sha}) | <div align="center">#{Bundles.format_bytes(bundle.install_size)}#{install_size_deviation}</div> | <div align="center">#{format_bundle_download_size(bundle.download_size)}#{download_size_deviation}</div> |
        """
      end)}
      """
    end
  end

  defp project_bundle_size_deviations(project, bundle) do
    last_bundle =
      Bundles.last_project_bundle(project, git_branch: project.default_branch, bundle: bundle)

    if is_nil(last_bundle) do
      {"", ""}
    else
      download_size_deviation =
        if is_nil(bundle.download_size) or is_nil(last_bundle.download_size) do
          ""
        else
          format_bundle_size_deviation(bundle.download_size, last_bundle.download_size)
        end

      {format_bundle_size_deviation(bundle.install_size, last_bundle.install_size), download_size_deviation}
    end
  end

  defp format_bundle_size_deviation(size, last_size) do
    deviation_percentage =
      ((size / last_size - 1) * 100) |> Decimal.from_float() |> Decimal.round(2)

    absolute_delta = abs(size - last_size)

    cond do
      size < last_size ->
        "<br/>`Δ -#{Bundles.format_bytes(absolute_delta)} (#{deviation_percentage}%)`"

      size > last_size ->
        "<br/>`Δ +#{Bundles.format_bytes(absolute_delta)} (+#{deviation_percentage}%)`"

      true ->
        ""
    end
  end

  defp format_bundle_download_size(nil), do: gettext("Unknown")
  defp format_bundle_download_size(size) when is_integer(size), do: Bundles.format_bytes(size)

  defp get_issue_id_from_git_ref(git_ref) do
    [issue_id, _merge] = git_ref |> String.split("/") |> Enum.take(-2)
    issue_id
  end

  defp get_latest_command_events(
         %{get_identifier: get_identifier, name: name, git_ref: git_ref, project: project},
         opts \\ []
       ) do
    filter = Keyword.get(opts, :filter, fn _ -> true end)

    %{
      name: name,
      git_ref: git_ref,
      project: project
    }
    |> CommandEvents.get_command_events_by_name_git_ref_and_project(preload: [:preview])
    |> Enum.filter(filter)
    |> Enum.reduce(%{}, fn command_event, acc ->
      identifier = get_identifier.(command_event)
      current_event = Map.get(acc, identifier)

      if current_event == nil or
           NaiveDateTime.after?(
             command_event.ran_at,
             current_event.ran_at
           ) do
        Map.put(acc, identifier, command_event)
      else
        acc
      end
    end)
    |> Map.values()
  end

  defp latest_previews(%{git_ref: git_ref, project: project}) do
    from(p in Preview)
    |> where([p], p.project_id == ^project.id and p.git_ref == ^git_ref)
    |> order_by([p], desc: p.inserted_at)
    |> distinct([p], p.display_name)
    |> Repo.all()
    |> Repo.preload(:app_builds)
  end

  defp get_previews_body(%{
         previews: previews,
         git_remote_url_origin: git_remote_url_origin,
         preview_url: preview_url,
         preview_qr_code_url: preview_qr_code_url,
         project: project
       }) do
    if Enum.empty?(previews) do
      nil
    else
      contains_ipas =
        previews |> Enum.flat_map(& &1.app_builds) |> Enum.any?(&(&1.type == :ipa))

      """

      #### Previews 📦

      | App | Commit |#{if contains_ipas, do: " Open on device |", else: ""}
      | - | - |#{if contains_ipas, do: " - |", else: ""}
      #{Enum.map(previews, fn preview ->
        git_commit_sha = preview.git_commit_sha
        preview_url = preview_url.(%{project: project, preview: preview})
        qr_code_image = get_qr_code_image(%{project: project, preview: preview, contains_ipas: contains_ipas, preview_qr_code_url: preview_qr_code_url})

        """
        | [#{preview.display_name}](#{preview_url}) | [#{String.slice(git_commit_sha, 0, 9)}](#{git_remote_url_origin}/commit/#{git_commit_sha}) |#{qr_code_image}
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
    case {AppBuilds.latest_ipa_app_build_for_preview(preview), contains_ipas} do
      {nil, true} ->
        " |"

      {nil, false} ->
        ""

      {_, _} ->
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

      #### Tests 🧪

      | Command | Status | Cache hit rate | Tests | Skipped | Ran | Commit |
      |:-:|:-:|:-:|:-:|:-:|:-:|:-:|
      #{Enum.map(test_command_events, fn test_command_event ->
        git_commit_sha = test_command_event.git_commit_sha
        total_number_of_tests = Enum.count(test_command_event.test_targets)
        tests_skipped = Enum.count(test_command_event.local_test_target_hits) + Enum.count(test_command_event.remote_test_target_hits)
        test_url = command_run_url.(%{project: project, command_event: test_command_event})

        """
        | [#{test_command_event.command_arguments}](#{test_url}) | #{get_status_text(test_command_event)} | #{get_cache_hit_rate(test_command_event)} | #{total_number_of_tests} | #{tests_skipped} | #{total_number_of_tests - tests_skipped} | [#{String.slice(git_commit_sha, 0, 9)}](#{git_remote_url_origin}/commit/#{git_commit_sha}) |
        """
      end)}
      """
    end
  end

  defp get_cache_hit_rate(command_event) do
    total_targets = Enum.count(command_event.cacheable_targets)

    total_hits =
      Enum.count(command_event.local_cache_target_hits) +
        Enum.count(command_event.remote_cache_target_hits)

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

  defp get_latest_builds(%{git_ref: git_ref, project: project}) do
    from(b in Runs.Build)
    |> where([b], b.project_id == ^project.id and b.git_ref == ^git_ref)
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
    |> Enum.filter(&(not is_nil(&1.scheme)))
    |> Enum.reduce(%{}, fn build, acc ->
      scheme = build.scheme

      current_build = Map.get(acc, scheme)

      if current_build == nil or
           NaiveDateTime.after?(
             build.inserted_at,
             current_build.inserted_at
           ) do
        Map.put(acc, scheme, build)
      else
        acc
      end
    end)
    |> Map.values()
  end

  defp get_builds_body(%{
         builds: builds,
         git_remote_url_origin: git_remote_url_origin,
         build_url: build_url,
         project: project
       }) do
    if Enum.empty?(builds) do
      nil
    else
      """

      #### Builds 🔨

      | Scheme | Status | Duration | Commit |
      |:-:|:-:|:-:|:-:|
      #{Enum.map(builds, fn build ->
        git_commit_sha = build.git_commit_sha
        build_url = build_url.(%{project: project, build: build})

        scheme = build.scheme
        duration = DateFormatter.format_duration_from_milliseconds(build.duration)

        """
        | [#{scheme}](#{build_url}) | #{get_build_status_text(build)} | #{duration} | [#{String.slice(git_commit_sha, 0, 9)}](#{git_remote_url_origin}/commit/#{git_commit_sha}) |
        """
      end)}
      """
    end
  end

  defp get_build_status_text(build) do
    case build.status do
      :failure -> "❌"
      :success -> "✅"
    end
  end
end
