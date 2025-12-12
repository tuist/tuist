defmodule Tuist.VCS do
  @moduledoc """
  A module that provides functions to interact with VCS repositories.
  """

  use Gettext, backend: TuistWeb.Gettext

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.Preview
  alias Tuist.Bundles
  alias Tuist.Bundles.Bundle
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.GitHub.Client
  alias Tuist.KeyValueStore
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Runs
  alias Tuist.Runs.Analytics
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias Tuist.VCS
  alias Tuist.VCS.GitHubAppInstallation

  @tuist_run_report_prefix "### 🛠️ Tuist Run Report 🛠️"

  @doc """
  Constructs a CI run URL based on the CI provider and metadata.
  Returns nil if the required CI information is missing.

  Accepts CI metadata as a map with:
  - ci_provider: atom (e.g., :github, :gitlab)
  - ci_run_id: string
  - ci_project_handle: string
  - ci_host: string (optional, for self-hosted instances)
  """
  def ci_run_url(%{ci_provider: provider, ci_run_id: run_id, ci_project_handle: project_handle} = ci_metadata)
      when not is_nil(run_id) and run_id != "" do
    host = Map.get(ci_metadata, :ci_host)
    host = if host == "", do: nil, else: host

    case {provider, project_handle} do
      {:github, project_handle} when not is_nil(project_handle) and project_handle != "" ->
        "https://github.com/#{project_handle}/actions/runs/#{run_id}"

      {:gitlab, project_path} when not is_nil(project_path) and project_path != "" ->
        gitlab_host = host || "gitlab.com"
        "https://#{gitlab_host}/#{project_path}/-/pipelines/#{run_id}"

      {:bitrise, _} ->
        "https://app.bitrise.io/build/#{run_id}"

      {:circleci, project_handle} when not is_nil(project_handle) and project_handle != "" ->
        "https://app.circleci.com/pipelines/github/#{project_handle}/#{run_id}"

      {:buildkite, project_handle} when not is_nil(project_handle) and project_handle != "" ->
        "https://buildkite.com/#{project_handle}/builds/#{run_id}"

      {:codemagic, project_id} when not is_nil(project_id) and project_id != "" ->
        "https://codemagic.io/app/#{project_id}/build/#{run_id}"

      _ ->
        nil
    end
  end

  def ci_run_url(_), do: nil

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

  def get_provider_from_repository_url(repository_url) do
    vcs_uri = URI.parse(repository_url)
    host = Map.get(vcs_uri, :host)

    case host do
      "github.com" -> {:ok, :github}
      _ -> {:error, :unsupported_vcs}
    end
  end

  defp get_client_for_provider(:github) do
    Client
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

  defp get_github_app_installation_id(%{repository_full_handle: repository_full_handle, project: project}) do
    project = Repo.preload(project, vcs_connection: :github_app_installation)

    with true <- Environment.github_app_configured?(),
         %{
           vcs_connection: %{
             repository_full_handle: connected_handle,
             github_app_installation: %{installation_id: installation_id}
           }
         } <- project,
         true <- String.downcase(connected_handle) == String.downcase(repository_full_handle) do
      {:ok, installation_id}
    else
      _ -> {:error, :not_found}
    end
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
    with true <- String.starts_with?(git_ref, "refs/pull/"),
         {:ok, installation_id} <-
           get_github_app_installation_id(%{repository_full_handle: repository_full_handle, project: project}) do
      client = get_client_for_provider(:github)
      issue_id = get_issue_id_from_git_ref(git_ref)

      client.create_comment(%{
        repository_full_handle: repository_full_handle,
        issue_id: issue_id,
        body: body,
        installation_id: installation_id
      })
    else
      false -> {:error, :not_pull_request}
      {:error, :not_found} -> {:error, :repository_not_connected}
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
    case get_github_app_installation_id(%{repository_full_handle: repository_full_handle, project: project}) do
      {:ok, installation_id} ->
        client = get_client_for_provider(:github)

        client.update_comment(%{
          repository_full_handle: repository_full_handle,
          comment_id: comment_id,
          body: body,
          installation_id: installation_id
        })

      {:error, :not_found} ->
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
        test_run_url: test_run_url,
        bundle_url: bundle_url,
        build_url: build_url
      }) do
    repository_full_handle =
      if is_nil(git_remote_url_origin) do
        nil
      else
        git_remote_url_origin |> get_repository_full_handle_from_url() |> elem(1)
      end

    with true <- not is_nil(git_commit_sha),
         true <- not is_nil(git_ref),
         true <- not is_nil(repository_full_handle),
         true <- String.starts_with?(git_ref, "refs/pull/"),
         {:ok, installation_id} <-
           get_github_app_installation_id(%{repository_full_handle: repository_full_handle, project: project}) do
      client = get_client_for_provider(:github)
      issue_id = get_issue_id_from_git_ref(git_ref)

      vcs_comment_body =
        get_vcs_comment_body(%{
          git_ref: git_ref,
          git_remote_url_origin: Projects.get_repository_url(project),
          preview_url: preview_url,
          preview_qr_code_url: preview_qr_code_url,
          test_run_url: test_run_url,
          build_url: build_url,
          bundle_url: bundle_url,
          project: project
        })

      existing_comment =
        get_existing_vcs_comment_id(%{
          client: client,
          repository: repository_full_handle,
          issue_id: issue_id,
          installation_id: installation_id
        })

      update_or_create_vcs_comment(%{
        vcs_comment_body: vcs_comment_body,
        repository: repository_full_handle,
        issue_id: issue_id,
        existing_comment: existing_comment,
        client: client,
        installation_id: installation_id
      })
    else
      # No GitHub app installation, skip posting comment
      _ -> :ok
    end
  end

  defp get_existing_vcs_comment_id(%{
         client: client,
         repository: repository,
         issue_id: issue_id,
         installation_id: installation_id
       }) do
    case client.get_comments(%{repository_full_handle: repository, issue_id: issue_id, installation_id: installation_id}) do
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
         client: client,
         installation_id: installation_id
       }) do
    cond do
      is_nil(vcs_comment_body) ->
        :ok

      is_nil(existing_comment) ->
        client.create_comment(%{
          repository_full_handle: repository,
          issue_id: issue_id,
          body: vcs_comment_body,
          installation_id: installation_id
        })

      true ->
        client.update_comment(%{
          repository_full_handle: repository,
          comment_id: existing_comment.id,
          body: vcs_comment_body,
          installation_id: installation_id
        })
    end
  end

  defp get_vcs_comment_body(%{
         git_ref: git_ref,
         git_remote_url_origin: git_remote_url_origin,
         preview_url: preview_url,
         preview_qr_code_url: preview_qr_code_url,
         test_run_url: test_run_url,
         build_url: build_url,
         bundle_url: bundle_url,
         project: project
       }) do
    previews =
      latest_previews(%{
        git_ref: git_ref,
        project: project
      })

    test_runs =
      get_latest_test_runs(%{
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
        test_runs: test_runs,
        git_remote_url_origin: git_remote_url_origin,
        test_run_url: test_run_url,
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
    git_ref_pattern = get_git_ref_pattern(git_ref)

    bundles =
      from(b in Bundle)
      |> where([b], b.project_id == ^project.id and like(b.git_ref, ^git_ref_pattern))
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
        | [#{bundle.name}](#{bundle_url.(%{project: project, bundle: bundle})}) | [#{String.slice(bundle.git_commit_sha, 0, 9)}](#{git_remote_url_origin}/commit/#{bundle.git_commit_sha}) | <div align="center">#{ByteFormatter.format_bytes(bundle.install_size)}#{install_size_deviation}</div> | <div align="center">#{format_bundle_download_size(bundle.download_size)}#{download_size_deviation}</div> |
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
        "<br/>`Δ -#{ByteFormatter.format_bytes(absolute_delta)} (#{deviation_percentage}%)`"

      size > last_size ->
        "<br/>`Δ +#{ByteFormatter.format_bytes(absolute_delta)} (+#{deviation_percentage}%)`"

      true ->
        ""
    end
  end

  defp format_bundle_download_size(nil), do: dgettext("dashboard_account", "Unknown")
  defp format_bundle_download_size(size) when is_integer(size), do: ByteFormatter.format_bytes(size)

  defp get_issue_id_from_git_ref(git_ref) do
    [issue_id, _merge] = git_ref |> String.split("/") |> Enum.take(-2)
    issue_id
  end

  defp get_git_ref_pattern(git_ref) do
    case String.split(git_ref, "/") do
      ["refs", "pull", pr_number, _suffix] -> "refs/pull/#{pr_number}/%"
      _ -> git_ref
    end
  end

  defp latest_previews(%{git_ref: git_ref, project: project}) do
    git_ref_pattern = get_git_ref_pattern(git_ref)

    from(p in Preview)
    |> where([p], p.project_id == ^project.id and like(p.git_ref, ^git_ref_pattern))
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
         test_runs: test_runs,
         git_remote_url_origin: git_remote_url_origin,
         test_run_url: test_run_url,
         project: project
       }) do
    if Enum.empty?(test_runs) do
      nil
    else
      project = Repo.preload(project, :account)

      metrics_data = Analytics.test_runs_metrics(test_runs)
      metrics_map = Map.new(metrics_data, &{&1.test_run_id, &1})

      """

      #### Tests 🧪

      | Scheme | Status | Cache hit rate | Tests | Skipped | Ran | Commit |
      |:-:|:-:|:-:|:-:|:-:|:-:|:-:|
      #{Enum.map(test_runs, fn test_run ->
        test_run_metrics = Map.get(metrics_map, test_run.id)

        git_commit_sha = test_run.git_commit_sha
        test_url = test_run_url.(%{project: project, test_run: test_run})
        scheme = if test_run.scheme == "", do: "Unknown", else: test_run.scheme

        cache_hit_rate = if test_run_metrics, do: test_run_metrics.cache_hit_rate, else: "0 %"
        total_tests = if test_run_metrics, do: test_run_metrics.total_tests, else: 0
        skipped_tests = if test_run_metrics, do: test_run_metrics.skipped_tests, else: 0
        ran_tests = if test_run_metrics, do: test_run_metrics.ran_tests, else: 0

        """
        | [#{scheme}](#{test_url}) | #{get_test_run_status_text(test_run)} | #{cache_hit_rate} | #{total_tests} | #{skipped_tests} | #{ran_tests} | [#{String.slice(git_commit_sha, 0, 9)}](#{git_remote_url_origin}/commit/#{git_commit_sha}) |
        """
      end)}
      """
    end
  end

  defp get_test_run_status_text(test_run) do
    case test_run.status do
      "failure" -> "❌"
      "success" -> "✅"
      "skipped" -> "⏭️"
    end
  end

  defp get_latest_builds(%{git_ref: git_ref, project: project}) do
    git_ref_pattern = get_git_ref_pattern(git_ref)

    from(b in Runs.Build)
    |> where([b], b.project_id == ^project.id and like(b.git_ref, ^git_ref_pattern))
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

  defp get_latest_test_runs(%{git_ref: git_ref, project: project}) do
    git_ref_pattern = get_git_ref_pattern(git_ref)

    from(t in Runs.Test)
    |> where([t], t.project_id == ^project.id and like(t.git_ref, ^git_ref_pattern))
    |> where([t], not is_nil(t.scheme) and t.scheme != "")
    |> order_by([t], desc: t.inserted_at)
    |> ClickHouseRepo.all()
    |> Enum.reduce(%{}, fn test_run, acc ->
      scheme = test_run.scheme

      current_test = Map.get(acc, scheme)

      if current_test == nil or
           NaiveDateTime.after?(
             test_run.inserted_at,
             current_test.inserted_at
           ) do
        Map.put(acc, scheme, test_run)
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

  # GitHub App Installation functions

  @doc """
  Gets a GitHub app installation by its installation ID.
  """
  def get_github_app_installation_by_installation_id(installation_id) do
    case Repo.get_by(GitHubAppInstallation, installation_id: to_string(installation_id)) do
      nil -> {:error, :not_found}
      github_app_installation -> {:ok, github_app_installation}
    end
  end

  @doc """
  Updates a GitHub app installation.
  """
  def update_github_app_installation(%GitHubAppInstallation{} = github_app_installation, attrs) do
    github_app_installation
    |> GitHubAppInstallation.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a new GitHub app installation.
  """
  def create_github_app_installation(attrs) do
    %GitHubAppInstallation{}
    |> GitHubAppInstallation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets repositories for a GitHub app installation.
  """
  def get_github_app_installation_repositories(%GitHubAppInstallation{installation_id: installation_id}) do
    KeyValueStore.get_or_update(
      [__MODULE__, "repositories", installation_id],
      [ttl: to_timeout(minute: 15)],
      fn ->
        # This can take long for organizations with a lot of repositories.
        # Ideally, we would only fetch this information once, store it in the database, and then sync the repositories via webhooks.
        # For now, we're sticking to this simple version.
        get_all_repositories_recursively(installation_id, [])
      end
    )
  end

  defp get_all_repositories_recursively(installation_id, accumulated_repos, opts \\ []) do
    case Client.list_installation_repositories(installation_id, opts) do
      {:ok, %{meta: %{next_url: next_url}, repositories: repositories}} ->
        all_repos = accumulated_repos ++ repositories

        case next_url do
          nil ->
            {:ok, all_repos}

          next_url ->
            get_all_repositories_recursively(installation_id, all_repos, next_url: next_url)
        end

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Deletes a GitHub app installation.
  """
  def delete_github_app_installation(%GitHubAppInstallation{} = github_app_installation) do
    Repo.delete(github_app_installation, stale_error_field: :id)
  end

  @doc """
  Get GitHub app installation URL with encrypted state parameter for account-specific installation.
  """
  def get_github_app_installation_url(%Account{id: account_id}) do
    app_name = Environment.github_app_name()
    state_token = generate_github_state_token(account_id)
    "https://github.com/apps/#{app_name}/installations/new?state=#{state_token}"
  end

  # GitHub State Token functions

  @doc """
  Generates a JWT state token for the given account ID.
  Returns the signed token string that should be used in the GitHub installation URL.
  """
  def generate_github_state_token(account_id) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "github_state", account_id)
  end

  @doc """
  Verifies the JWT state token to extract the account ID.
  Returns {:ok, account_id} if valid, {:error, reason} if invalid or expired.
  """
  def verify_github_state_token(token) do
    # 90 days
    token_max_age_seconds = 7_776_000
    Phoenix.Token.verify(TuistWeb.Endpoint, "github_state", token, max_age: token_max_age_seconds)
  end
end
