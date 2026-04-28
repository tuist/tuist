defmodule Tuist.VCS do
  @moduledoc """
  A module that provides functions to interact with VCS repositories.
  """

  use Gettext, backend: TuistWeb.Gettext

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.Preview
  alias Tuist.Builds
  alias Tuist.Bundles
  alias Tuist.Bundles.Bundle
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.GitHub.Client
  alias Tuist.Gradle
  alias Tuist.KeyValueStore
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Tests.Analytics, as: TestsAnalytics
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias Tuist.VCS.GitHubAppInstallation
  alias Tuist.VCS.Workers.CommentWorker

  @tuist_run_report_prefix "### 🛠️ Tuist Run Report 🛠️"
  @max_flaky_tests_in_comment 5
  @max_failed_tests_in_comment 5

  @doc """
  Constructs a CI run URL based on the CI provider and metadata.
  Returns nil if the required CI information is missing.

  Accepts CI metadata as a map with:
  - ci_provider: atom (e.g., :github, :gitlab)
  - ci_run_id: string
  - ci_project_handle: string
  - ci_host: string (optional, for self-hosted instances)
  """
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def ci_run_url(%{ci_provider: provider, ci_run_id: run_id, ci_project_handle: project_handle} = ci_metadata)
      when run_id != "" do
    host = Map.get(ci_metadata, :ci_host)
    host = if host == "", do: nil, else: host

    case {provider, project_handle} do
      {"github", project_handle} when project_handle != "" ->
        "https://github.com/#{project_handle}/actions/runs/#{run_id}"

      {"gitlab", project_path} when project_path != "" ->
        gitlab_host = host || "gitlab.com"
        "https://#{gitlab_host}/#{project_path}/-/pipelines/#{run_id}"

      {"bitrise", _} ->
        "https://app.bitrise.io/build/#{run_id}"

      {"circleci", project_handle} when project_handle != "" ->
        "https://app.circleci.com/pipelines/github/#{project_handle}/#{run_id}"

      {"buildkite", project_handle} when project_handle != "" ->
        "https://buildkite.com/#{project_handle}/builds/#{run_id}"

      {"codemagic", project_id} when project_id != "" ->
        "https://codemagic.io/app/#{project_id}/build/#{run_id}"

      _ ->
        nil
    end
  end

  def ci_run_url(_), do: nil

  def supported_vcs_hosts do
    ["GitHub"]
  end

  @default_provider :github

  @doc """
  Default base URL for a forge provider when no custom instance is configured.
  """
  def default_client_url(provider \\ @default_provider)
  def default_client_url(:github), do: "https://github.com"

  @doc """
  REST API base URL for a given forge provider and instance URL.

  github.com is special-cased to use the dedicated `api.github.com`
  hostname; self-hosted GitHub Enterprise Server instances expose the
  REST API under `/api/v3` on the same host.
  """
  def api_url(provider, client_url)
  def api_url(:github, nil), do: api_url(:github, default_client_url(:github))
  def api_url(:github, "https://github.com"), do: "https://api.github.com"

  def api_url(:github, client_url) when is_binary(client_url) do
    client_url |> String.trim_trailing("/") |> Kernel.<>("/api/v3")
  end

  @doc """
  Convenience overload that returns the API base URL for an installation.
  Raises if the input is not a recognised installation struct/map.
  """
  def installation_api_url(%GitHubAppInstallation{client_url: client_url}), do: api_url(:github, client_url)

  def installation_api_url(%{client_url: client_url}) when is_binary(client_url), do: api_url(:github, client_url)

  @doc """
  Validates a user-supplied `client_url` for a forge instance. Returns
  `{:ok, normalized_url}` on success or `{:error, reason}` otherwise.

  This is a *shape* check — it verifies the URL has an http(s) scheme and a
  non-empty host, and trims trailing slashes. It deliberately does not perform
  DNS resolution: SSRF protection happens at request time via
  `Tuist.OAuth2.SSRFGuard.pin/1` so a TOCTOU rebinding attack between
  validation and request cannot bypass it.
  """
  def validate_client_url(url) when is_binary(url) do
    trimmed = url |> String.trim() |> String.trim_trailing("/")

    case URI.parse(trimmed) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, trimmed}

      _ ->
        {:error, :invalid_url}
    end
  end

  def validate_client_url(_), do: {:error, :invalid_url}

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

  # NOTE: this only recognises github.com because the few callers that use it
  # (mainly Swift package registry resolution from raw repo URLs) target the
  # public Tuist instance. GitHub Enterprise Server flows reach the GitHub
  # provider through a stored `GitHubAppInstallation` instead, so they don't
  # depend on this function. If a GHES-aware caller appears, broaden this to
  # accept hosts that match a known installation's `client_url`.
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

  defp get_github_app_installation_for_repository(%{repository_full_handle: repository_full_handle, project: project}) do
    project = Repo.preload(project, vcs_connection: :github_app_installation)

    with true <- Environment.github_app_configured?(),
         %{
           vcs_connection: %{
             repository_full_handle: connected_handle,
             github_app_installation: %GitHubAppInstallation{} = installation
           }
         } <- project,
         true <- String.downcase(connected_handle) == String.downcase(repository_full_handle) do
      {:ok, installation}
    else
      _ -> {:error, :not_found}
    end
  end

  def enqueue_vcs_pull_request_comment(args) do
    # Schedule the comment worker after a delay to allow ClickHouse ingestion
    # buffers to flush. Without this, data inserted just before enqueuing
    # (e.g. builds) may not yet be queryable when the worker runs.
    flush_interval_seconds = div(Environment.clickhouse_flush_interval_ms(), 1000)
    schedule_in = flush_interval_seconds + 1

    args
    |> CommentWorker.new(schedule_in: schedule_in)
    |> Oban.insert()
  end

  @doc """
  Creates a comment on a VCS issue/pull request.
  """
  def create_comment(%{repository_full_handle: repository_full_handle, git_ref: git_ref, body: body, project: project}) do
    with true <- String.starts_with?(git_ref, "refs/pull/"),
         {:ok, installation} <-
           get_github_app_installation_for_repository(%{
             repository_full_handle: repository_full_handle,
             project: project
           }) do
      client = get_client_for_provider(:github)
      issue_id = get_issue_id_from_git_ref(git_ref)

      client.create_comment(%{
        repository_full_handle: repository_full_handle,
        issue_id: issue_id,
        body: body,
        installation: installation
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
    case get_github_app_installation_for_repository(%{
           repository_full_handle: repository_full_handle,
           project: project
         }) do
      {:ok, installation} ->
        client = get_client_for_provider(:github)

        client.update_comment(%{
          repository_full_handle: repository_full_handle,
          comment_id: comment_id,
          body: body,
          installation: installation
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

    with true <- git_commit_sha != "",
         true <- not is_nil(git_ref) and git_ref != "",
         true <- not is_nil(repository_full_handle),
         true <- String.starts_with?(git_ref, "refs/pull/"),
         {:ok, installation} <-
           get_github_app_installation_for_repository(%{
             repository_full_handle: repository_full_handle,
             project: project
           }) do
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
          installation: installation
        })

      update_or_create_vcs_comment(%{
        vcs_comment_body: vcs_comment_body,
        repository: repository_full_handle,
        issue_id: issue_id,
        existing_comment: existing_comment,
        client: client,
        installation: installation
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
         installation: installation
       }) do
    comments_params = %{
      repository_full_handle: repository,
      issue_id: issue_id,
      installation: installation
    }

    case client.get_comments(comments_params) do
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
         installation: installation
       }) do
    cond do
      is_nil(vcs_comment_body) ->
        :ok

      is_nil(existing_comment) ->
        client.create_comment(%{
          repository_full_handle: repository,
          issue_id: issue_id,
          body: vcs_comment_body,
          installation: installation
        })

      true ->
        client.update_comment(%{
          repository_full_handle: repository,
          comment_id: existing_comment.id,
          body: vcs_comment_body,
          installation: installation
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

    gradle_builds =
      get_latest_gradle_builds(%{
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
        gradle_builds: gradle_builds,
        git_remote_url_origin: git_remote_url_origin,
        build_url: build_url,
        project: project
      })

    flaky_tests_body =
      get_flaky_tests_body(%{
        test_runs: test_runs,
        project: project
      })

    failed_tests_body =
      get_failed_tests_body(%{
        test_runs: test_runs,
        project: project
      })

    bodies = [previews_body, test_body, failed_tests_body, flaky_tests_body, builds_body, bundles_body]

    if Enum.all?(bodies, &is_nil/1) do
      nil
    else
      """
      #{@tuist_run_report_prefix}
      """ <> Enum.map_join(bodies, "", &(&1 || ""))
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

      {xcode_runs, gradle_runs} = Enum.split_with(test_runs, &(&1.build_system != "gradle"))
      has_multiple_build_systems = xcode_runs != [] and gradle_runs != []

      xcode_body =
        get_xcode_test_body(%{
          test_runs: xcode_runs,
          git_remote_url_origin: git_remote_url_origin,
          test_run_url: test_run_url,
          project: project
        })

      gradle_body =
        get_gradle_test_body(%{
          test_runs: gradle_runs,
          git_remote_url_origin: git_remote_url_origin,
          test_run_url: test_run_url,
          project: project
        })

      xcode_section =
        if has_multiple_build_systems and xcode_body != "", do: "##### Xcode\n\n" <> xcode_body, else: xcode_body

      gradle_section =
        if has_multiple_build_systems and gradle_body != "", do: "\n##### Gradle\n\n" <> gradle_body, else: gradle_body

      """

      #### Tests 🧪

      #{xcode_section}#{gradle_section}
      """
    end
  end

  defp get_xcode_test_body(%{test_runs: [], project: _project} = _args), do: ""

  defp get_xcode_test_body(%{
         test_runs: test_runs,
         git_remote_url_origin: git_remote_url_origin,
         test_run_url: test_run_url,
         project: project
       }) do
    metrics_data = TestsAnalytics.test_runs_metrics(project.id, test_runs)
    metrics_map = Map.new(metrics_data, &{&1.test_run_id, &1})

    rows =
      Enum.map_join(test_runs, "", fn test_run ->
        test_run_metrics = Map.get(metrics_map, test_run.id)

        git_commit_sha = test_run.git_commit_sha
        test_url = test_run_url.(%{project: project, test_run: test_run})
        scheme = if test_run.scheme == "", do: "Unknown", else: test_run.scheme

        cache_hit_rate = if test_run_metrics, do: test_run_metrics.cache_hit_rate, else: "0 %"
        total_tests = if test_run_metrics, do: test_run_metrics.total_tests, else: 0
        skipped_tests = if test_run_metrics, do: test_run_metrics.skipped_tests, else: 0
        ran_tests = if test_run_metrics, do: test_run_metrics.ran_tests, else: 0

        "| [#{scheme}](#{test_url}) | #{get_test_run_status_text(test_run)} | #{cache_hit_rate} | #{total_tests} | #{skipped_tests} | #{ran_tests} | [#{String.slice(git_commit_sha, 0, 9)}](#{git_remote_url_origin}/commit/#{git_commit_sha}) |\n"
      end)

    "| Scheme | Status | Cache hit rate | Tests | Skipped | Ran | Commit |\n" <>
      "|:-:|:-:|:-:|:-:|:-:|:-:|:-:|\n" <>
      rows
  end

  defp get_gradle_test_body(%{test_runs: [], project: _project} = _args), do: ""

  defp get_gradle_test_body(%{
         test_runs: test_runs,
         git_remote_url_origin: git_remote_url_origin,
         test_run_url: test_run_url,
         project: project
       }) do
    metrics_data = TestsAnalytics.test_runs_metrics(project.id, test_runs)
    metrics_map = Map.new(metrics_data, &{&1.test_run_id, &1})

    rows =
      Enum.map_join(test_runs, "", fn test_run ->
        test_run_metrics = Map.get(metrics_map, test_run.id)

        git_commit_sha = test_run.git_commit_sha
        test_url = test_run_url.(%{project: project, test_run: test_run})
        scheme = if test_run.scheme == "", do: "Unknown", else: test_run.scheme
        total_tests = if test_run_metrics, do: test_run_metrics.total_tests, else: 0

        "| [#{scheme}](#{test_url}) | #{get_test_run_status_text(test_run)} | #{total_tests} | [#{String.slice(git_commit_sha, 0, 9)}](#{git_remote_url_origin}/commit/#{git_commit_sha}) |\n"
      end)

    "| Project | Status | Tests | Commit |\n" <>
      "|:-:|:-:|:-:|:-:|\n" <>
      rows
  end

  defp get_test_run_status_text(test_run) do
    case test_run.status do
      "failure" -> "❌"
      "success" -> "✅"
      "skipped" -> "⏭️"
    end
  end

  defp get_flaky_tests_body(%{test_runs: test_runs, project: project}) do
    flaky_tests_by_run =
      test_runs
      |> Enum.map(fn test_run ->
        flaky_tests = Tests.get_flaky_runs_for_test_run(test_run.id)
        {test_run, flaky_tests}
      end)
      |> Enum.filter(fn {_test_run, flaky_tests} -> Enum.any?(flaky_tests) end)

    if Enum.empty?(flaky_tests_by_run) do
      nil
    else
      project = Repo.preload(project, :account)

      all_flaky_tests =
        flaky_tests_by_run
        |> Enum.flat_map(fn {_test_run, flaky_tests} -> flaky_tests end)
        |> Enum.uniq_by(& &1.test_case_id)

      total_flaky_count = length(all_flaky_tests)
      displayed_flaky_tests = Enum.take(all_flaky_tests, @max_flaky_tests_in_comment)

      runs_summary =
        Enum.map_join(flaky_tests_by_run, "", fn {test_run, flaky_tests} ->
          flaky_count = length(flaky_tests)
          scheme = if test_run.scheme == "" or is_nil(test_run.scheme), do: "Unknown", else: test_run.scheme

          flaky_runs_url =
            Environment.app_url(
              path: "/#{project.account.name}/#{project.name}/tests/test-runs/#{test_run.id}?tab=flaky-runs"
            )

          "- **#{scheme}**: #{flaky_count} flaky #{if flaky_count == 1, do: "test", else: "tests"} ([View all](#{flaky_runs_url}))\n"
        end)

      more_tests_note =
        if total_flaky_count > @max_flaky_tests_in_comment do
          "\n> Showing #{@max_flaky_tests_in_comment} of #{total_flaky_count} flaky tests. See links above for full details.\n"
        else
          ""
        end

      """

      #### Flaky Tests ⚠️

      #{runs_summary}
      | Test case | Module | Suite |
      |:-|:-|:-|
      #{Enum.map_join(displayed_flaky_tests, "", fn flaky_test ->
        test_case_url = Environment.app_url(path: "/#{project.account.name}/#{project.name}/tests/test-cases/#{flaky_test.test_case_id}")

        """
        | [#{flaky_test.name}](#{test_case_url}) | #{flaky_test.module_name} | #{flaky_test.suite_name} |
        """
      end)}#{more_tests_note}
      """
    end
  end

  defp get_failed_tests_body(%{test_runs: test_runs, project: project}) do
    failed_runs_with_counts =
      test_runs
      |> Enum.filter(&(&1.status == "failure"))
      |> Enum.map(fn test_run ->
        filters = [
          %{field: :test_run_id, op: :==, value: test_run.id},
          %{field: :status, op: :==, value: "failure"},
          %{field: :is_flaky, op: :==, value: false}
        ]

        {failed_test_case_runs, meta} =
          Tests.list_test_case_runs(
            %{
              filters: filters,
              page: 1,
              page_size: @max_failed_tests_in_comment,
              order_by: [:ran_at],
              order_directions: [:desc]
            },
            preload: [:failures]
          )

        {test_run, failed_test_case_runs, meta.total_count}
      end)
      |> Enum.filter(fn {_test_run, _runs, total_count} -> total_count > 0 end)

    if Enum.empty?(failed_runs_with_counts) do
      nil
    else
      project = Repo.preload(project, [:account, :vcs_connection])

      total_failed_count =
        Enum.reduce(failed_runs_with_counts, 0, fn {_, _, count}, acc -> acc + count end)

      displayed_failed_tests =
        failed_runs_with_counts
        |> Enum.flat_map(fn {test_run, failed_test_case_runs, _count} ->
          Enum.map(failed_test_case_runs, fn tcr ->
            %{
              test_case_id: tcr.test_case_id,
              name: tcr.name,
              module_name: tcr.module_name,
              suite_name: tcr.suite_name,
              failure: List.first(tcr.failures),
              git_commit_sha: test_run.git_commit_sha
            }
          end)
        end)
        |> Enum.uniq_by(& &1.test_case_id)
        |> Enum.take(@max_failed_tests_in_comment)

      runs_summary =
        Enum.map_join(failed_runs_with_counts, "", fn {test_run, _runs, failed_count} ->
          scheme = if test_run.scheme == "" or is_nil(test_run.scheme), do: "Unknown", else: test_run.scheme

          failures_url =
            Environment.app_url(
              path: "/#{project.account.name}/#{project.name}/tests/test-runs/#{test_run.id}?tab=failures"
            )

          "- **#{scheme}**: #{failed_count} failed #{if failed_count == 1, do: "test", else: "tests"} ([View all](#{failures_url}))\n"
        end)

      more_tests_note =
        if total_failed_count > @max_failed_tests_in_comment do
          "\n> Showing #{@max_failed_tests_in_comment} of #{total_failed_count} failed tests. See links above for full details.\n"
        else
          ""
        end

      failed_tests_list =
        Enum.map_join(displayed_failed_tests, "", &format_failed_test_item(&1, project))

      """

      #### Failed Tests ❌

      #{runs_summary}
      #{failed_tests_list}#{more_tests_note}
      """
    end
  end

  defp format_failed_test_item(failed_test, project) do
    test_case_url =
      Environment.app_url(path: "/#{project.account.name}/#{project.name}/tests/test-cases/#{failed_test.test_case_id}")

    subtitle =
      case {failed_test.module_name, failed_test.suite_name} do
        {m, s} when m not in [nil, ""] and s not in [nil, ""] -> " · #{m} · #{s}"
        {m, _} when m not in [nil, ""] -> " · #{m}"
        _ -> ""
      end

    failure_detail = format_failure_detail(failed_test.failure, project, failed_test.git_commit_sha)

    "- [**#{failed_test.name}**](#{test_case_url})#{subtitle}\\\n#{failure_detail}\n"
  end

  @max_failure_message_length 160

  defp format_failure_detail(nil, _project, _commit_sha), do: ""

  defp format_failure_detail(failure, project, commit_sha) do
    location = format_failure_location(failure, project, commit_sha)
    message = sanitize_for_markdown(failure.message)

    case {location, message} do
      {nil, nil} -> ""
      {loc, nil} -> loc
      {nil, msg} -> truncate_message(msg)
      {loc, msg} -> "#{loc}: #{truncate_message(msg)}"
    end
  end

  defp format_failure_location(%{path: path} = failure, project, commit_sha) when path not in [nil, ""] do
    location_text = "#{path}:#{failure.line_number}"
    repo_handle = project.vcs_connection && project.vcs_connection.repository_full_handle

    if repo_handle && commit_sha not in [nil, ""] do
      "[`#{location_text}`](https://github.com/#{repo_handle}/blob/#{commit_sha}/#{path}#L#{failure.line_number})"
    else
      "`#{location_text}`"
    end
  end

  defp format_failure_location(_, _, _), do: nil

  defp sanitize_for_markdown(nil), do: nil

  defp sanitize_for_markdown(message) do
    message |> String.replace(~r/[\n\r]+/, " ") |> String.trim()
  end

  defp truncate_message(message) do
    if String.length(message) > @max_failure_message_length do
      String.slice(message, 0, @max_failure_message_length) <> "…"
    else
      message
    end
  end

  defp get_latest_builds(%{git_ref: git_ref, project: project}) do
    git_ref_pattern = get_git_ref_pattern(git_ref)

    from(b in Builds.Build)
    |> where([b], b.project_id == ^project.id and like(b.git_ref, ^git_ref_pattern))
    |> where([b], b.status not in ["processing", "failed_processing"])
    |> order_by([b], desc: b.inserted_at)
    |> ClickHouseRepo.all()
    |> Enum.filter(&(&1.scheme != ""))
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

  defp get_latest_gradle_builds(%{git_ref: git_ref, project: project}) do
    git_ref_pattern = get_git_ref_pattern(git_ref)

    from(b in Gradle.Build)
    |> where([b], b.project_id == ^project.id and like(b.git_ref, ^git_ref_pattern))
    |> order_by([b], desc: b.inserted_at)
    |> ClickHouseRepo.all()
    |> Enum.filter(&(&1.root_project_name != ""))
    |> Enum.reduce(%{}, fn build, acc ->
      name = build.root_project_name

      current_build = Map.get(acc, name)

      if current_build == nil or
           NaiveDateTime.after?(
             build.inserted_at,
             current_build.inserted_at
           ) do
        Map.put(acc, name, build)
      else
        acc
      end
    end)
    |> Map.values()
  end

  defp get_latest_test_runs(%{git_ref: git_ref, project: project}) do
    git_ref_pattern = get_git_ref_pattern(git_ref)

    from(t in Tests.Test)
    |> where([t], t.project_id == ^project.id and like(t.git_ref, ^git_ref_pattern))
    |> where([t], t.scheme != "")
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
         gradle_builds: gradle_builds,
         git_remote_url_origin: git_remote_url_origin,
         build_url: build_url,
         project: project
       }) do
    if Enum.empty?(builds) and Enum.empty?(gradle_builds) do
      nil
    else
      has_multiple_build_systems = builds != [] and gradle_builds != []

      xcode_body =
        get_xcode_builds_body(%{
          builds: builds,
          git_remote_url_origin: git_remote_url_origin,
          build_url: build_url,
          project: project
        })

      gradle_body =
        get_gradle_builds_body(%{
          builds: gradle_builds,
          git_remote_url_origin: git_remote_url_origin,
          build_url: build_url,
          project: project
        })

      xcode_section =
        if has_multiple_build_systems and xcode_body != "", do: "##### Xcode\n\n" <> xcode_body, else: xcode_body

      gradle_section =
        if has_multiple_build_systems and gradle_body != "", do: "\n##### Gradle\n\n" <> gradle_body, else: gradle_body

      """

      #### Builds 🔨

      #{xcode_section}#{gradle_section}
      """
    end
  end

  defp get_xcode_builds_body(%{builds: [], project: _project} = _args), do: ""

  defp get_xcode_builds_body(%{
         builds: builds,
         git_remote_url_origin: git_remote_url_origin,
         build_url: build_url,
         project: project
       }) do
    rows =
      Enum.map_join(builds, "", fn build ->
        url = build_url.(%{project: project, build: %{id: build.id}})
        duration = DateFormatter.format_duration_from_milliseconds(build.duration)

        "| [#{build.scheme}](#{url}) | #{get_build_status_text(build)} | #{duration} | [#{String.slice(build.git_commit_sha, 0, 9)}](#{git_remote_url_origin}/commit/#{build.git_commit_sha}) |\n"
      end)

    "| Scheme | Status | Duration | Commit |\n" <>
      "|:-:|:-:|:-:|:-:|\n" <>
      rows
  end

  defp get_gradle_builds_body(%{builds: [], project: _project} = _args), do: ""

  defp get_gradle_builds_body(%{
         builds: builds,
         git_remote_url_origin: git_remote_url_origin,
         build_url: build_url,
         project: project
       }) do
    rows =
      Enum.map_join(builds, "", fn build ->
        url = build_url.(%{project: project, build: %{id: build.id}})
        duration = DateFormatter.format_duration_from_milliseconds(build.duration_ms)

        "| [#{build.root_project_name}](#{url}) | #{get_build_status_text(build)} | #{duration} | [#{String.slice(build.git_commit_sha, 0, 9)}](#{git_remote_url_origin}/commit/#{build.git_commit_sha}) |\n"
      end)

    "| Project | Status | Duration | Commit |\n" <>
      "|:-:|:-:|:-:|:-:|\n" <>
      rows
  end

  defp get_build_status_text(build) do
    case build.status do
      "failure" -> "❌"
      "success" -> "✅"
      "cancelled" -> "🚫"
      _ -> "❓"
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
  def get_github_app_installation_repositories(%GitHubAppInstallation{} = installation) do
    KeyValueStore.get_or_update(
      [__MODULE__, "repositories", installation_api_url(installation), installation.installation_id],
      [ttl: to_timeout(minute: 15)],
      fn ->
        # This can take long for organizations with a lot of repositories.
        # Ideally, we would only fetch this information once, store it in the database,
        # and then sync the repositories via webhooks.
        # For now, we're sticking to this simple version.
        get_all_repositories_recursively(installation, [])
      end
    )
  end

  defp get_all_repositories_recursively(installation, opts, accumulated_repos \\ []) do
    case Client.list_installation_repositories(installation, opts) do
      {:ok, %{meta: %{next_url: next_url}, repositories: repositories}} ->
        all_repos = accumulated_repos ++ repositories

        case next_url do
          nil ->
            {:ok, all_repos}

          next_url ->
            get_all_repositories_recursively(
              installation,
              Keyword.put(opts, :next_url, next_url),
              all_repos
            )
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

  Accepts an optional `:client_url` to target a self-hosted GitHub Enterprise Server instance,
  defaulting to https://github.com.
  """
  def get_github_app_installation_url(%Account{id: account_id}, opts \\ []) do
    client_url = normalize_client_url(Keyword.get(opts, :client_url))
    app_name = Environment.github_app_name()
    state_token = generate_github_state_token(account_id, client_url)
    "#{client_url}/apps/#{app_name}/installations/new?state=#{state_token}"
  end

  defp normalize_client_url(nil), do: default_client_url()
  defp normalize_client_url(""), do: default_client_url()

  defp normalize_client_url(url) when is_binary(url), do: url |> String.trim() |> String.trim_trailing("/")

  # GitHub State Token functions

  @doc """
  Generates a signed state token for the given account ID and target GitHub
  client URL. The token round-trips through GitHub's installation flow so we
  know which GitHub instance the resulting installation belongs to.
  """
  def generate_github_state_token(account_id, client_url \\ default_client_url()) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "github_state", {account_id, normalize_client_url(client_url)})
  end

  @doc """
  Verifies the state token. Returns `{:ok, %{account_id: id, client_url: url}}`
  on success, `{:error, reason}` otherwise. Tokens generated before client_url
  was introduced are accepted with the default github.com URL.
  """
  def verify_github_state_token(token) do
    # 90 days
    token_max_age_seconds = 7_776_000

    case Phoenix.Token.verify(TuistWeb.Endpoint, "github_state", token, max_age: token_max_age_seconds) do
      {:ok, {account_id, client_url}} when is_integer(account_id) and is_binary(client_url) ->
        {:ok, %{account_id: account_id, client_url: normalize_client_url(client_url)}}

      {:ok, account_id} when is_integer(account_id) ->
        {:ok, %{account_id: account_id, client_url: default_client_url()}}

      {:ok, _} ->
        {:error, :invalid}

      {:error, _reason} = error ->
        error
    end
  end

  def update_check_run(params), do: Client.update_check_run(params)
end
