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
  alias Tuist.Cargo
  alias Tuist.ClickHouseCapabilities
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.GitHub.Client
  alias Tuist.Gradle
  alias Tuist.KeyValueStore
  alias Tuist.Origin
  alias Tuist.Origin.Client, as: OriginClient
  alias Tuist.Origin.Installation, as: OriginInstallation
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Projects.VCSConnection
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Tests.Analytics, as: TestsAnalytics
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias Tuist.VCS.GitHubAppInstallation
  alias Tuist.VCS.RemoteURL
  alias Tuist.VCS.Workers.CommentWorker

  @tuist_run_report_prefix "### 🛠️ Tuist Run Report 🛠️"
  @tuist_run_report_footer "\n<sub>Reported by [Tuist](https://tuist.dev), faster builds and reliable tests for Xcode, Gradle, Bazel, and more.</sub>\n"
  @max_flaky_tests_in_comment 5
  @max_failed_tests_in_comment 5
  @max_coverage_rows_in_comment 10
  @test_body_build_systems [
    {"xcode", "Xcode"},
    {"gradle", "Gradle"},
    {"bazel", "Bazel"},
    {"mix", "Mix"},
    {"cargo", "Cargo"}
  ]

  # Per-webhook lookup cache: every inbound GitHub webhook calls
  # `list_github_app_installations_for_webhook/2` once before HMAC
  # verification, so memoising the result keeps that PG read off the
  # request path under burst load. The TTL is short enough that any
  # install / uninstall / re-register flow heals within a minute,
  # and the only field a stale entry could mis-serve (`webhook_secret`)
  # is rotated through `replace_github_app_installation/2` whose flow
  # already spans longer than the TTL.
  @webhook_installations_cache_ttl_ms 60_000

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
        "https://app.circleci.com/jobs/github/#{project_handle}/#{run_id}"

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
    ["GitHub", "Origin"]
  end

  @default_provider :github

  @doc """
  Default base URL for a forge provider when no custom instance is configured.
  """
  def default_client_url(provider \\ @default_provider)
  def default_client_url(:github), do: "https://github.com"
  def default_client_url(:origin), do: "https://cursor.com/codebase"

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
  def installation_api_url(%{client_url: client_url, api_url: api_url})
      when is_binary(client_url) and is_binary(api_url) and api_url != "", do: api_url

  def installation_api_url(%GitHubAppInstallation{client_url: client_url}), do: api_url(:github, client_url)

  def installation_api_url(%{client_url: client_url}) when is_binary(client_url), do: api_url(:github, client_url)

  @doc """
  Validates a user-supplied `client_url` for a forge instance. Returns
  `{:ok, normalized_url}` on success or `{:error, reason}` otherwise.

  This is a *shape* check — it verifies the URL has an https scheme and a
  non-empty host, and trims trailing slashes. The scheme is restricted to
  https because the manifest exchange transports a fresh GitHub App's
  private key, client secret, and webhook secret; allowing http would
  expose those credentials in transit. http:// is permitted only for
  the dev/test envs so local fixtures (e.g. `http://localhost:4002`)
  keep working.

  The validator deliberately does not perform DNS resolution: SSRF
  protection happens at request time via `Tuist.OAuth2.SSRFGuard.pin/1`
  so a TOCTOU rebinding attack between validation and request cannot
  bypass it.
  """
  def validate_client_url(url) when is_binary(url) do
    trimmed = url |> String.trim() |> String.trim_trailing("/")

    case URI.parse(trimmed) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        {:ok, trimmed}

      %URI{scheme: "http", host: host} when is_binary(host) and host != "" ->
        if Environment.env() in [:dev, :test] do
          {:ok, trimmed}
        else
          {:error, :insecure_scheme}
        end

      _ ->
        {:error, :invalid_url}
    end
  end

  def validate_client_url(_), do: {:error, :invalid_url}

  @doc """
  Validates an optional REST API base URL, including any proxy path prefix.
  Empty values use the API derived from the browser URL. Credentials, query
  strings, and fragments are rejected; DNS and public-IP checks run at request
  time, just as they do for installations without an override.
  """
  def validate_api_url(url) when url in [nil, ""], do: {:ok, nil}

  def validate_api_url(url) when is_binary(url) do
    case String.trim(url) do
      "" ->
        {:ok, nil}

      trimmed ->
        with {:ok, normalized} <- validate_client_url(trimmed),
             %URI{host: host, userinfo: nil, query: nil, fragment: nil} <- URI.parse(normalized),
             false <- public_github_host?(host) do
          {:ok, normalized}
        else
          _ -> {:error, :invalid_url}
        end
    end
  end

  def validate_api_url(_), do: {:error, :invalid_url}

  defp public_github_host?(host) do
    host = host |> String.downcase() |> String.trim_trailing(".")
    host == "github.com" or String.ends_with?(host, ".github.com")
  end

  @doc """
  Rebases an API pagination link onto the configured transport endpoint.
  GitHub Enterprise can emit its canonical browser host in Link headers.
  Only the configured API or canonical API origin and path prefix are accepted.
  """
  def github_api_request_url(url, client_url, api_url) do
    request = URI.parse(url)
    transport = URI.parse(api_url)
    canonical = URI.parse(api_url(:github, client_url))

    cond do
      api_url_under_base?(request, transport) ->
        {:ok, url}

      api_url_under_base?(request, canonical) ->
        suffix = String.replace_prefix(request.path, canonical.path || "", "")
        {:ok, URI.to_string(%{transport | path: (transport.path || "") <> suffix, query: request.query})}

      true ->
        {:error, "GitHub API pagination URL does not match the configured instance"}
    end
  end

  defp api_url_under_base?(%URI{userinfo: nil, fragment: nil, path: path, host: host} = request, base)
       when is_binary(path) and is_binary(host) do
    same_api_origin?(request, base) and safe_api_path?(path) and api_path_under_base?(path, base.path || "")
  end

  defp api_url_under_base?(_, _), do: false

  defp same_api_origin?(request, base) do
    request.scheme == base.scheme and String.downcase(request.host) == String.downcase(base.host) and
      request.port == base.port
  end

  defp api_path_under_base?(path, prefix), do: path == prefix or String.starts_with?(path, prefix <> "/")

  defp safe_api_path?(path) do
    if Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, path) do
      false
    else
      path
      |> URI.decode()
      |> String.split(["/", "\\"])
      |> Enum.all?(&(&1 not in [".", ".."]))
    end
  end

  @doc """
  Returns the GitHub App credentials Tuist should use to act on behalf of
  a given installation: an installation that has its own credentials (via
  the App manifest flow on GHES) wins, otherwise we fall back to the
  globally-configured env vars (which target github.com).

  Returns `%{app_name, client_id, client_secret, private_key, webhook_secret, app_id}`
  or `nil` if neither source has usable credentials.
  """
  def github_app_credentials(installation \\ nil)

  def github_app_credentials(%GitHubAppInstallation{
        app_id: app_id,
        client_id: client_id,
        client_secret: client_secret,
        private_key: private_key,
        webhook_secret: webhook_secret,
        app_slug: app_slug
      })
      when is_binary(app_id) and is_binary(client_id) and is_binary(private_key) do
    %{
      app_name: app_slug,
      app_id: app_id,
      client_id: client_id,
      client_secret: client_secret,
      private_key: private_key,
      webhook_secret: webhook_secret
    }
  end

  def github_app_credentials(_) do
    if Environment.github_app_configured?() do
      %{
        app_name: Environment.github_app_name(),
        # github.com uses the app's client_id as the JWT issuer
        app_id: Environment.github_app_client_id(),
        client_id: Environment.github_app_client_id(),
        client_secret: Environment.github_app_client_secret(),
        private_key: Environment.github_app_private_key(),
        webhook_secret: Environment.github_app_webhook_secret()
      }
    end
  end

  @doc """
  Returns the distinct GitHub Apps Tuist should act as for App-level
  operations (e.g. webhook delivery log introspection). Each item is
  `%{credentials, api_url, client_url}`.

  Includes the globally-configured github.com App when the env-var
  credentials are present, plus any per-installation Apps registered
  via the GHES manifest flow (deduped by `(app_id, client_url)`, so
  multiple installations on the same GHES App produce one entry).
  """
  def list_github_apps do
    global =
      case github_app_credentials() do
        %{} = creds -> [%{credentials: creds, api_url: api_url(:github, nil), client_url: default_client_url()}]
        _ -> []
      end

    per_installation =
      GitHubAppInstallation
      |> where([i], not is_nil(i.app_id) and not is_nil(i.private_key))
      |> Repo.all()
      |> Enum.uniq_by(fn i -> {i.app_id, i.client_url} end)
      |> Enum.map(fn installation ->
        case github_app_credentials(installation) do
          %{} = creds ->
            %{credentials: creds, api_url: installation_api_url(installation), client_url: installation.client_url}

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    global ++ per_installation
  end

  def get_repository_content(params, opts \\ [])
  def get_repository_content(%{provider: :origin}, _opts), do: {:error, :unsupported_vcs}

  def get_repository_content(%{repository_full_handle: repository_full_handle, provider: provider, token: token}, opts) do
    client = get_client_for_provider(provider)

    client.get_repository_content(
      %{
        repository_full_handle: repository_full_handle,
        token: token
      },
      opts
    )
  end

  def get_tags(%{provider: :origin}), do: {:error, :unsupported_vcs}

  def get_tags(%{provider: provider, repository_full_handle: repository_full_handle, token: token}) do
    client = get_client_for_provider(provider)

    client.get_tags(%{repository_full_handle: repository_full_handle, token: token})
  end

  def get_source_archive_by_tag_and_repository_full_handle(%{provider: :origin}), do: {:error, :unsupported_vcs}

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

  # Public GitHub and Origin URLs are recognized here. Enterprise Server
  # flows use their stored installation instead of guessing a provider from
  # an arbitrary host. Origin supports reports, not package-registry content.
  def get_provider_from_repository_url(repository_url) do
    vcs_uri = repository_url |> normalize_scp_url() |> URI.parse()
    host = String.downcase(vcs_uri.host || "")

    case host do
      "github.com" ->
        {:ok, :github}

      "origin.cursor.com" ->
        {:ok, :origin}

      "cursor.com" ->
        if(String.starts_with?(vcs_uri.path || "", "/codebase/"),
          do: {:ok, :origin},
          else: {:error, :unsupported_vcs}
        )

      _ ->
        {:error, :unsupported_vcs}
    end
  end

  defp get_client_for_provider(:github) do
    Client
  end

  def get_repository_full_handle_from_url(repository_url) when is_binary(repository_url) do
    uri = repository_url |> normalize_scp_url() |> URI.parse()
    path = uri.path || ""

    path =
      case String.downcase(uri.host || "") do
        "origin.cursor.com" -> String.replace_prefix(path, "/git/", "/")
        "cursor.com" -> String.replace_prefix(path, "/codebase/", "/")
        _ -> path
      end

    full_handle = path |> String.trim("/") |> String.replace_trailing(".git", "")

    if Regex.match?(~r{^[\w.-]+/[\w.-]+$}, full_handle) do
      {:ok, full_handle}
    else
      {:error, :invalid_repository_url}
    end
  end

  def get_repository_full_handle_from_url(_), do: {:error, :invalid_repository_url}

  defp normalize_scp_url(url), do: Regex.replace(~r/^git@([^:]+):/, url, "https://\\1/")

  defp get_app_installation_for_repository(%{project: project, repository_full_handle: handle} = params) do
    case Repo.preload(project, :vcs_connection).vcs_connection do
      %{provider: :origin} -> Origin.installation_for_repository(project, handle)
      _ -> get_github_app_installation_for_repository(params)
    end
  end

  defp comment_client(%OriginInstallation{}), do: OriginClient
  defp comment_client(%GitHubAppInstallation{}), do: Client

  defp report_pull_request(%OriginInstallation{} = installation, handle, ref, sha, remote) do
    case get_provider_from_repository_url(remote) do
      {:ok, :origin} ->
        OriginClient.get_pull_request_number(%{
          installation: installation,
          repository_full_handle: handle,
          git_ref: ref,
          git_commit_sha: sha
        })

      _ ->
        {:error, :not_pull_request}
    end
  end

  defp report_pull_request(%GitHubAppInstallation{}, _handle, ref, _sha, remote) do
    if get_provider_from_repository_url(remote) == {:ok, :origin} do
      {:error, :not_pull_request}
    else
      case pull_request_number_from_git_ref(ref) do
        nil -> {:error, :not_pull_request}
        number -> {:ok, number}
      end
    end
  end

  defp get_github_app_installation_for_repository(%{repository_full_handle: repository_full_handle, project: project}) do
    project = Repo.preload(project, vcs_connection: :github_app_installation)

    with %{
           vcs_connection: %{
             repository_full_handle: connected_handle,
             github_app_installation: %GitHubAppInstallation{} = installation
           }
         } <- project,
         true <- String.downcase(connected_handle) == String.downcase(repository_full_handle),
         %{} <- github_app_credentials(installation) do
      {:ok, installation}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Looks a VCS user up by username, through the project's connected repository.

  Returns the provider's durable id alongside the canonical username. The
  username is what a person types and can be changed later, and the id is
  what survives that, so callers that need to recognise the same person
  again should keep the id.
  """
  def get_user_by_username(%{username: username, project: project}) do
    project = Repo.preload(project, vcs_connection: :github_app_installation)

    with %{
           vcs_connection: %{
             provider: provider,
             repository_full_handle: repository_full_handle,
             github_app_installation: %GitHubAppInstallation{} = installation
           }
         } <- project,
         %{} <- github_app_credentials(installation) do
      provider
      |> get_client_for_provider()
      |> then(
        & &1.get_repository_user_by_username(%{
          repository_full_handle: repository_full_handle,
          username: username,
          installation: installation
        })
      )
    else
      _ -> {:error, :no_vcs_connection}
    end
  end

  def enqueue_vcs_pull_request_comment(args) do
    # Schedule the comment worker after a delay to allow ClickHouse ingestion
    # buffers to flush. Without this, data inserted just before enqueuing
    # (e.g. builds) may not yet be queryable when the worker runs.
    flush_interval_seconds = div(Environment.clickhouse_flush_interval_ms(), 1000)
    schedule_in = flush_interval_seconds + 1

    # Entire Trail reports are queued by the comment worker, not here: build
    # and xcresult processors call this function, and their database role
    # cannot read `entire_trail_connections`.
    args
    |> RemoteURL.strip_credentials_from_params()
    |> CommentWorker.new(schedule_in: schedule_in)
    |> Oban.insert()
  end

  @doc """
  Queues the pull request comment of a commit whose coverage was just folded
  complete (`Tuist.Tests.Coverage.Commits.recompute/3`): the completion
  signal, or a run landing after it. The runs' own reports queue the comment
  too, but before their fold, so that comment can't show the figure. The
  pull request's ref is the newest one the commit's signed runs reported.

  Unlike the other reports, this one isn't folded into a comment job that is
  already running: that job may have read the commit before the fold, so a
  job of its own follows it (and cancels it, `CommentWorker`).
  """
  def enqueue_coverage_pull_request_comment(
        %Project{} = project,
        %{complete: true, pull_request_number: number} = summary
      )
      when number > 0 do
    with true <- project.vcs_comments_enabled,
         remote when is_binary(remote) <- Projects.get_repository_url(project),
         git_ref when is_binary(git_ref) <- pull_request_git_ref(summary) do
      %{
        git_commit_sha: summary.git_commit_sha,
        git_ref: git_ref,
        git_remote_url_origin: remote,
        project_id: project.id
      }
      |> CommentWorker.new(unique: [keys: [:project_id, :git_ref], states: [:available, :scheduled], period: :infinity])
      |> Oban.insert()
    else
      _ -> :skipped
    end
  end

  def enqueue_coverage_pull_request_comment(_project, _summary), do: :skipped

  defp pull_request_git_ref(summary) do
    ClickHouseRepo.one(
      from(t in Coverage.Commits.measured_runs_query(summary),
        where: t.is_pull_request and t.git_ref != "",
        order_by: [desc: t.inserted_at],
        limit: 1,
        select: t.git_ref
      )
    )
  end

  @doc """
  Returns the pull request number of a `refs/pull/<number>/<suffix>` git ref,
  such as `refs/pull/23958/merge`, or `nil` for any other ref.
  """
  def pull_request_number_from_git_ref("refs/pull/" <> rest) do
    case Integer.parse(rest) do
      {number, ""} when number > 0 -> number
      {number, "/" <> _suffix} when number > 0 -> number
      _ -> nil
    end
  end

  def pull_request_number_from_git_ref(_git_ref), do: nil

  @doc """
  Creates a comment on a VCS issue/pull request.
  """
  def create_comment(%{repository_full_handle: repository_full_handle, git_ref: git_ref, body: body, project: project}) do
    with issue_id when is_integer(issue_id) <- pull_request_number_from_git_ref(git_ref),
         {:ok, installation} <-
           get_app_installation_for_repository(%{
             repository_full_handle: repository_full_handle,
             project: project
           }) do
      client = comment_client(installation)

      client.create_comment(%{
        repository_full_handle: repository_full_handle,
        issue_id: issue_id,
        body: body,
        installation: installation
      })
    else
      nil -> {:error, :not_pull_request}
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
    case get_app_installation_for_repository(%{
           repository_full_handle: repository_full_handle,
           project: project
         }) do
      {:ok, installation} ->
        client = comment_client(installation)

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

  def post_vcs_pull_request_comment(
        %{
          git_ref: git_ref,
          git_remote_url_origin: git_remote_url_origin,
          git_commit_sha: git_commit_sha,
          project: project,
          preview_url: preview_url,
          preview_qr_code_url: preview_qr_code_url,
          test_run_url: test_run_url,
          bundle_url: bundle_url,
          build_url: build_url
        } = params
      ) do
    with true <- project.vcs_comments_enabled,
         true <- is_binary(git_commit_sha) and git_commit_sha != "",
         true <- is_binary(git_ref) and git_ref != "",
         {:ok, repository_full_handle} <-
           get_repository_full_handle_from_url(git_remote_url_origin),
         {:ok, installation} <-
           get_app_installation_for_repository(%{
             repository_full_handle: repository_full_handle,
             project: project
           }),
         {:ok, issue_id} <-
           report_pull_request(
             installation,
             repository_full_handle,
             git_ref,
             git_commit_sha,
             git_remote_url_origin
           ),
         client = comment_client(installation),
         {:ok, existing_comment} <-
           get_existing_vcs_comment_id(%{
             client: client,
             repository: repository_full_handle,
             issue_id: issue_id,
             installation: installation
           }) do
      vcs_comment_body =
        %{
          git_ref: git_ref,
          git_remote_url_origin: Projects.get_repository_url(project),
          preview_url: preview_url,
          preview_qr_code_url: preview_qr_code_url,
          test_run_url: test_run_url,
          build_url: build_url,
          bundle_url: bundle_url,
          coverage_url: Map.get(params, :coverage_url),
          project: project
        }
        |> get_run_report()
        |> with_run_report_footer()

      update_or_create_vcs_comment(%{
        vcs_comment_body: vcs_comment_body,
        repository: repository_full_handle,
        issue_id: issue_id,
        existing_comment: existing_comment,
        client: client,
        installation: installation
      })
    else
      {:error, reason} when reason in [:not_found, :not_pull_request, :invalid_repository_url] ->
        :ok

      {:error, _} = error ->
        error

      _ ->
        :ok
    end
  end

  # Reviewers who have never heard of Tuist read these comments, so hosted
  # comments say what Tuist is. Self-hosted instances keep the report alone.
  defp with_run_report_footer(nil), do: nil

  defp with_run_report_footer(body) do
    if Environment.tuist_hosted?(), do: body <> @tuist_run_report_footer, else: body
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

    expected_client_id =
      case installation do
        %OriginInstallation{app_id: app_id} ->
          app_id

        %GitHubAppInstallation{} ->
          case github_app_credentials(installation) do
            %{client_id: client_id} -> client_id
            _ -> nil
          end
      end

    case client.get_comments(comments_params) do
      {:ok, comments} ->
        {:ok,
         Enum.find(comments, fn comment ->
           not is_nil(expected_client_id) and comment.client_id == expected_client_id and
             String.starts_with?(comment.body, @tuist_run_report_prefix)
         end)}

      {:error, _} = error ->
        error
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

  @doc """
  Renders the latest previews, tests, builds, and bundles for a project.

  When `:git_commit_sha` is provided, results match that exact commit regardless
  of their Git ref. Otherwise, results match `:git_ref`, including both head and
  merge refs for a pull request. Returns nil when no results are available.
  """
  def get_run_report(params) do
    case get_run_report_sections(params) do
      nil -> nil
      report -> report.summary
    end
  end

  @doc "Returns the report and its actionable test sections from the same insight snapshot."
  def get_run_report_sections(
        %{
          git_remote_url_origin: git_remote_url_origin,
          preview_url: preview_url,
          preview_qr_code_url: preview_qr_code_url,
          test_run_url: test_run_url,
          build_url: build_url,
          bundle_url: bundle_url,
          project: project
        } = params
      ) do
    query_params = Map.take(params, [:project, :git_ref, :git_commit_sha])
    previews = latest_previews(query_params)
    test_runs = get_latest_test_runs(query_params)
    builds = get_latest_builds(query_params)
    gradle_builds = get_latest_gradle_builds(query_params)

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
      bundles_body(
        Map.merge(query_params, %{
          git_remote_url_origin: git_remote_url_origin,
          bundle_url: bundle_url
        })
      )

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

    coverage_body =
      get_coverage_body(%{
        project: project,
        sha: Map.get(params, :git_commit_sha) || newest_test_run_commit_sha(test_runs),
        pull_request_number: pull_request_number_from_git_ref(Map.get(params, :git_ref)),
        git_remote_url_origin: git_remote_url_origin,
        coverage_url: Map.get(params, :coverage_url)
      })

    bodies = [
      previews_body,
      test_body,
      failed_tests_body,
      flaky_tests_body,
      coverage_body,
      builds_body,
      bundles_body
    ]

    if Enum.all?(bodies, &is_nil/1) do
      nil
    else
      %{
        summary:
          """
          #{@tuist_run_report_prefix}
          """ <> Enum.map_join(bodies, "", &(&1 || "")),
        failed_tests: failed_tests_body,
        flaky_tests: flaky_tests_body
      }
    end
  end

  defp bundles_body(%{project: project, git_remote_url_origin: git_remote_url_origin, bundle_url: bundle_url} = params) do
    # ClickHouse runs `DISTINCT` before `ORDER BY`, so deduping against
    # `b.name` in the query would pick an arbitrary row per name and
    # report stale bundle sizes. Fetch rows ordered by `inserted_at`
    # first and keep the newest per name in Elixir. Bounded by the
    # commit or `git_ref` pattern so the scan stays small.
    bundles =
      from(b in Bundle)
      |> filter_run_report_query(params)
      |> order_by([b], desc: b.inserted_at)
      |> ClickHouseRepo.all()
      |> Enum.uniq_by(& &1.name)

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
        | [#{bundle.name}](#{bundle_url.(%{project: project, bundle: bundle})}) | #{commit_link(bundle.git_commit_sha, git_remote_url_origin)} | <div align="center">#{ByteFormatter.format_bytes(bundle.install_size)}#{install_size_deviation}</div> | <div align="center">#{format_bundle_download_size(bundle.download_size)}#{download_size_deviation}</div> |
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

  # A pull request's coverage is its latest commit's: the commit of its newest
  # signed test run, the latest commit the Tests section reports. Not the
  # commit the comment was queued for, which may be an earlier commit whose
  # build or preview finished after the newer commit's coverage was reported.
  defp newest_test_run_commit_sha([]), do: nil

  defp newest_test_run_commit_sha(test_runs), do: Enum.max_by(test_runs, & &1.inserted_at, NaiveDateTime).git_commit_sha

  # Coverage is reported only once the commit's pipeline signalled
  # completion: before then a scheme or shard may still be missing, so the
  # section says it is in progress rather than showing a figure that may
  # move. An incomplete figure is a lower bound, shown as such without a
  # change.
  defp get_coverage_body(%{sha: sha}) when sha in [nil, ""], do: nil

  defp get_coverage_body(%{project: project, sha: sha} = args) do
    if Coverage.supported?(project) do
      case Comparison.compare(project, sha, files: @max_coverage_rows_in_comment) do
        nil -> nil
        comparison -> coverage_section(comparison, %{args | project: Repo.preload(project, :account)})
      end
    end
  end

  defp coverage_section(%{status: :in_progress}, %{sha: sha, git_remote_url_origin: remote} = args) do
    """

    #### Coverage ☂️

    ⏳ Coverage for #{commit_link(sha, remote)} is still being collected. It's reported here once every test run of the commit has reported and the pipeline signals completion (`tuist coverage complete`).#{coverage_details_link(args)}
    """
  end

  defp coverage_section(%{status: :incomplete, head: head}, %{sha: sha, git_remote_url_origin: remote} = args) do
    """

    #### Coverage ☂️

    ⚠️ Coverage for #{commit_link(sha, remote)} is incomplete: **#{head.coverage}%** is a lower bound, since #{incomplete_reason(head)}, so it isn't compared with the base.#{coverage_details_link(args)}
    """
  end

  defp coverage_section(%{status: :complete} = comparison, %{sha: sha, git_remote_url_origin: remote} = args) do
    %{head: head, change: change} = comparison
    change_text = if change, do: " `Δ #{signed_points(change)}`", else: " `Δ unknown`"

    """

    #### Coverage ☂️

    **#{head.coverage}%**#{change_text} (#{format_number(head.covered_lines)} of #{format_number(head.executable_lines)} lines) at #{commit_link(sha, remote)}

    #{coverage_base_text(comparison, args)}#{coverage_details_link(args)}
    #{coverage_targets_table(comparison, args.project)}#{coverage_files_table(comparison)}
    """
  end

  # Why the figure is a lower bound, in the order the coverage page explains
  # it (`TuistWeb.Coverage.Components.incomplete_title/1`).
  defp incomplete_reason(head) do
    reasons = Coverage.Commits.gap_reasons(head)

    cond do
      :dirty_run_excluded in reasons ->
        "some schemes only ran on a checkout with uncommitted changes, whose coverage doesn't count"

      :run_data_unavailable in reasons ->
        "some of the runs' data couldn't be read in time"

      :uninstrumented_code in reasons ->
        "some of the code the tests ran came from the binary cache without coverage counters"

      true ->
        "the coverage of some tests the runs skipped couldn't be determined"
    end
  end

  defp coverage_base_text(%{requested_base_sha: nil}, _args),
    do: "The pull request's base commit isn't known, so the change is unknown."

  defp coverage_base_text(%{base: nil} = comparison, args),
    do:
      "Neither the base commit #{requested_base_link(comparison, args)} nor any of its ancestors on the base branch has complete coverage, so the change is unknown."

  defp coverage_base_text(%{requested_base_sha: requested, base: %{git_commit_sha: requested}}, args),
    do: "Compared with the base commit #{coverage_commit_link(requested, args)}."

  defp coverage_base_text(%{base: base} = comparison, args) do
    commits = if base.distance == 1, do: "1 commit", else: "#{base.distance} commits"

    "Compared with #{coverage_commit_link(base.git_commit_sha, args)}, the nearest ancestor of the base commit #{requested_base_link(comparison, args)} with complete coverage (#{commits} earlier)."
  end

  # A base commit no run measured has no coverage page, so it links to the
  # repository like the comment's other commits.
  defp requested_base_link(%{requested_base_sha: sha, requested_base_measured: true}, args),
    do: coverage_commit_link(sha, args)

  defp requested_base_link(%{requested_base_sha: sha}, args), do: commit_link(sha, args.git_remote_url_origin)

  # A base commit opens its coverage page, which is what the comparison read.
  defp coverage_commit_link(sha, %{coverage_url: url, project: project}) when is_function(url, 1),
    do: "[#{String.slice(sha, 0, 9)}](#{url.(%{project: project, sha: sha, pull_request_number: nil})})"

  defp coverage_commit_link(sha, args), do: commit_link(sha, args.git_remote_url_origin)

  # The pull request's coverage page when the report is for one, else the
  # commit's.
  defp coverage_details_link(%{coverage_url: url} = args) when is_function(url, 1),
    do: " [View coverage](#{url.(Map.take(args, [:project, :sha, :pull_request_number]))})"

  defp coverage_details_link(_args), do: ""

  # With a base, the modules whose coverage changed, most first, and how many
  # didn't; a module the base didn't have counts as changed. Without a base no
  # change is known, so the least covered. Mix calls modules applications and
  # Cargo packages; Xcode targets and Gradle projects are modules, as the Tests
  # section and Module Cache call them.
  defp coverage_targets_table(%{targets: []}, _project), do: ""

  defp coverage_targets_table(%{base: nil, targets: targets}, project) do
    shown = targets |> Enum.sort_by(&{&1.coverage, &1.name}) |> Enum.take(@max_coverage_rows_in_comment)
    more = length(targets) - length(shown)

    coverage_targets_rows(shown, project, if(more > 0, do: "#{more} more not shown."))
  end

  defp coverage_targets_table(%{targets: targets}, project) do
    {changed, unchanged} = Enum.split_with(targets, &(&1.change != 0.0))

    shown =
      changed
      |> Enum.sort_by(&{-abs(&1.change || 0.0), &1.coverage, &1.name})
      |> Enum.take(@max_coverage_rows_in_comment)

    more = length(changed) - length(shown)

    note =
      [
        if(more > 0, do: "#{more} more changed not shown."),
        if(unchanged != [], do: "#{count_modules(length(unchanged), project)} unchanged.")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    coverage_targets_rows(shown, project, note)
  end

  defp coverage_targets_rows(targets, project, note) do
    rows =
      if targets == [],
        do: "",
        else: """

        | #{coverage_target_label(project)} | Coverage | Δ |
        | - | - | - |
        #{Enum.map_join(targets, "\n", fn target -> "| #{escape_table_cell(target.name)} | #{target.coverage}% | #{coverage_change_cell(target.change)} |" end)}
        """

    note = if note in [nil, ""], do: "", else: "\n<sub>#{note}</sub>\n"
    rows <> note
  end

  defp count_modules(1, project), do: "1 #{String.downcase(coverage_target_label(project))}"
  defp count_modules(count, project), do: "#{count} #{String.downcase(coverage_target_label(project))}s"

  defp coverage_files_table(%{changed_files: []}), do: ""

  defp coverage_files_table(%{changed_files: files}) do
    """

    <details>
    <summary>Files whose coverage changed most</summary>

    | File | Coverage | Δ |
    | - | - | - |
    #{Enum.map_join(files, "\n", fn file -> "| `#{escape_table_cell(file.path)}` | #{Coverage.percentage(file.covered_lines, file.executable_lines)}% | #{coverage_change_cell(file.change)} |" end)}

    </details>
    """
  end

  defp coverage_target_label(%Project{build_system: :mix}), do: "Application"
  defp coverage_target_label(%Project{build_system: :cargo}), do: "Package"
  defp coverage_target_label(_project), do: "Module"

  defp coverage_change_cell(nil), do: "—"
  defp coverage_change_cell(change), do: "`#{signed_points(change)}`"

  defp signed_points(change) when change > 0, do: "+#{change}%"
  defp signed_points(change), do: "#{change}%"

  defp escape_table_cell(text), do: String.replace(text, "|", "\\|")

  defp format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp commit_link(nil, _git_remote_url_origin), do: ""

  defp commit_link(git_commit_sha, nil), do: "`#{String.slice(git_commit_sha, 0, 9)}`"

  defp commit_link(git_commit_sha, "https://cursor.com/codebase/" <> _repository),
    do: "`#{String.slice(git_commit_sha, 0, 9)}`"

  defp commit_link(git_commit_sha, git_remote_url_origin),
    do: "[#{String.slice(git_commit_sha, 0, 9)}](#{git_remote_url_origin}/commit/#{git_commit_sha})"

  defp get_git_ref_pattern(git_ref) do
    case String.split(git_ref, "/") do
      ["refs", "pull", pr_number, _suffix] -> "refs/pull/#{pr_number}/%"
      _ -> git_ref
    end
  end

  defp filter_run_report_query(query, %{project: project} = params) do
    query = where(query, [result], result.project_id == ^project.id)

    case Map.get(params, :git_commit_sha) do
      nil ->
        git_ref_pattern = params |> Map.fetch!(:git_ref) |> get_git_ref_pattern()
        where(query, [result], like(result.git_ref, ^git_ref_pattern))

      git_commit_sha ->
        where(query, [result], result.git_commit_sha == ^git_commit_sha)
    end
  end

  defp latest_previews(params) do
    from(p in Preview)
    |> filter_run_report_query(params)
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
        preview_url = preview_url.(%{project: project, preview: preview})
        qr_code_image = get_qr_code_image(%{project: project, preview: preview, contains_ipas: contains_ipas, preview_qr_code_url: preview_qr_code_url})

        """
        | [#{preview.display_name}](#{preview_url})#{run_command(preview, preview_url)} | #{commit_link(preview.git_commit_sha, git_remote_url_origin)} |#{qr_code_image}
        """
      end)}
      """
    end
  end

  # Command-line previews have no install page or QR code; `tuist run` is how
  # people and agents try them.
  defp run_command(preview, preview_url) do
    if Enum.any?(preview.app_builds, &(&1.type == :executable)),
      do: "<br/>`tuist run #{preview_url}`",
      else: ""
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

  defp get_test_body(%{test_runs: []}), do: nil

  defp get_test_body(%{
         test_runs: test_runs,
         git_remote_url_origin: git_remote_url_origin,
         test_run_url: test_run_url,
         project: project
       }) do
    project = Repo.preload(project, :account)
    runs_by_build_system = Enum.group_by(test_runs, & &1.build_system)

    sections =
      for {build_system, name} <- @test_body_build_systems,
          build_system_test_runs = Map.get(runs_by_build_system, build_system, []),
          build_system_test_runs != [] do
        args = test_body_args(build_system_test_runs, project, git_remote_url_origin, test_run_url)

        body =
          if build_system == "xcode",
            do: get_xcode_test_body(args),
            else: get_test_rollup_body(args)

        {name, body}
      end

    section_body =
      case sections do
        [] -> nil
        [{_name, body}] -> body
        sections -> Enum.map_join(sections, "\n", fn {name, body} -> "##### #{name}\n\n#{body}" end)
      end

    if section_body do
      """

      #### Tests 🧪

      #{section_body}
      """
    end
  end

  defp test_body_args(test_runs, project, git_remote_url_origin, test_run_url) do
    %{
      test_runs: test_runs,
      git_remote_url_origin: git_remote_url_origin,
      test_run_url: test_run_url,
      project: project
    }
  end

  defp get_xcode_test_body(%{
         test_runs: test_runs,
         git_remote_url_origin: git_remote_url_origin,
         test_run_url: test_run_url,
         project: project
       }) do
    metrics_map = project.id |> TestsAnalytics.test_runs_metrics(test_runs) |> Map.new(&{&1.test_run_id, &1})
    runs = Enum.map(test_runs, &{&1, Map.fetch!(metrics_map, &1.id)})
    any_run? = fn field -> Enum.any?(runs, fn {_test_run, metrics} -> Map.fetch!(metrics, field) end) end

    columns =
      Enum.filter(
        [
          {"Scheme", true,
           fn {test_run, _metrics} ->
             scheme = if test_run.scheme == "", do: "Unknown", else: test_run.scheme
             "[#{scheme}](#{test_run_url.(%{project: project, test_run: test_run})})"
           end},
          {"Status", true, fn {test_run, _metrics} -> get_test_run_status_text(test_run) end},
          {"Module cache hit rate", any_run?.(:module_cache_hit_rate),
           fn {_test_run, metrics} -> metrics.module_cache_hit_rate || "-" end},
          {"Xcode cache hit rate", any_run?.(:xcode_cache_hit_rate),
           fn {_test_run, metrics} -> metrics.xcode_cache_hit_rate || "-" end},
          {"Ran test modules", true, fn {_test_run, metrics} -> test_modules_text(metrics) end},
          {"Commit", true, fn {test_run, _metrics} -> commit_link(test_run.git_commit_sha, git_remote_url_origin) end}
        ],
        fn {_header, shown?, _cell} -> shown? end
      )

    "| #{Enum.map_join(columns, " | ", fn {header, _, _} -> header end)} |\n" <>
      "|#{Enum.map_join(columns, "|", fn _ -> ":-:" end)}|\n" <>
      Enum.map_join(runs, "", fn run -> "| #{Enum.map_join(columns, " | ", fn {_, _, cell} -> cell.(run) end)} |\n" end)
  end

  defp test_modules_text(%{has_selective_testing_data: true} = metrics),
    do: "#{metrics.ran_test_modules}/#{metrics.ran_test_modules + metrics.skipped_test_modules}"

  defp test_modules_text(metrics), do: metrics.ran_test_modules

  defp get_test_rollup_body(%{
         test_runs: [latest | _] = test_runs,
         git_remote_url_origin: git_remote_url_origin,
         test_run_url: test_run_url,
         project: project
       }) do
    counts = TestsAnalytics.test_case_counts(project.id, test_runs)

    links =
      Enum.map_join(test_runs, "<br/>", fn test_run ->
        name = test_run_name(test_run)
        "[#{name}](#{test_run_url.(%{project: project, test_run: test_run})})"
      end)

    "| Test runs | Status | Passed | Failed | Skipped | Commit |\n" <>
      "|:-:|:-:|:-:|:-:|:-:|:-:|\n" <>
      "| #{links} | #{rollup_status_text(test_runs, counts)} | #{counts.passed} | #{counts.failed} | #{counts.skipped} | #{commit_link(latest.git_commit_sha, git_remote_url_origin)} |\n"
  end

  defp test_run_name(%{build_system: "cargo", scheme: scheme}), do: Cargo.test_run_label(scheme)
  defp test_run_name(%{scheme: scheme}) when scheme in [nil, ""], do: "Unknown"
  defp test_run_name(%{scheme: scheme}), do: scheme

  defp rollup_status_text(test_runs, counts) do
    statuses = Enum.map(test_runs, & &1.status)

    cond do
      Enum.any?(statuses, &(&1 in ["in_progress", "processing"])) -> "⏳"
      counts.failed > 0 or "failure" in statuses -> "❌"
      "failed_processing" in statuses -> "⚠️"
      Enum.all?(statuses, &(&1 == "skipped")) -> "⏭️"
      true -> "✅"
    end
  end

  defp get_test_run_status_text(test_run) do
    case test_run.status do
      "failure" -> "❌"
      "success" -> "✅"
      "skipped" -> "⏭️"
      "in_progress" -> "⏳"
      "processing" -> "⏳"
      "failed_processing" -> "⚠️"
      _ -> "❓"
    end
  end

  defp get_flaky_tests_body(%{test_runs: test_runs, project: project}) do
    # Batched lookup: one round-trip against `test_case_runs_by_test_run` for
    # every test run on the PR instead of N. This is the dominant query in the
    # post-CI burst when several schemes report at once. The comment only lists
    # test cases, so the runs' failures and repetitions are not loaded.
    flaky_runs_by_test_run_id =
      test_runs |> Enum.map(& &1.id) |> Tests.get_flaky_runs_for_test_runs(details: false)

    flaky_tests_by_run =
      test_runs
      |> Enum.map(fn test_run ->
        flaky_tests = Map.get(flaky_runs_by_test_run_id, test_run.id, [])
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
          scheme = test_run_name(test_run)

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
          scheme = test_run_name(test_run)

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

    "- [**#{failed_test.name}**](#{test_case_url})#{subtitle}#{failure_detail}\n"
  end

  @max_failure_message_length 160
  @max_failure_message_lines 10

  defp format_failure_detail(nil, _project, _commit_sha), do: ""

  defp format_failure_detail(failure, project, commit_sha) do
    location = format_failure_location(failure, project, commit_sha)

    case {location, failure_message_lines(failure.message)} do
      {nil, []} -> ""
      {loc, []} -> "\\\n#{loc}"
      {nil, [line]} -> "\\\n#{truncate_message(line)}"
      {loc, [line]} -> "\\\n#{loc}: #{truncate_message(line)}"
      {nil, lines} -> "\n\n#{format_failure_code_block(lines)}"
      {loc, lines} -> "\\\n#{loc}\n\n#{format_failure_code_block(lines)}"
    end
  end

  defp failure_message_lines(nil), do: []

  defp failure_message_lines(message) do
    case String.trim(message) do
      "" -> []
      trimmed -> trimmed |> String.split(~r/\r\n|\r|\n/) |> Enum.map(&String.trim_trailing/1)
    end
  end

  defp format_failure_code_block(lines) do
    {shown_lines, hidden_lines} = Enum.split(lines, @max_failure_message_lines)
    shown_lines = Enum.map(shown_lines, &truncate_message/1)
    shown_lines = if hidden_lines == [], do: shown_lines, else: shown_lines ++ ["…"]
    fence = code_fence(shown_lines)

    Enum.map_join([fence | shown_lines] ++ [fence], "\n", &"  #{&1}")
  end

  defp code_fence(lines) do
    longest_backtick_run =
      lines
      |> Enum.flat_map(&Regex.scan(~r/`+/, &1))
      |> Enum.map(fn [run] -> String.length(run) end)
      |> Enum.max(fn -> 0 end)

    String.duplicate("`", max(3, longest_backtick_run + 1))
  end

  defp format_failure_location(%{path: path} = failure, project, commit_sha) when path not in [nil, ""] do
    location_text = "#{path}:#{failure.line_number}"
    repo_handle = project.vcs_connection && project.vcs_connection.repository_full_handle

    if repo_handle && project.vcs_connection.provider == :github && commit_sha not in [nil, ""] do
      "[`#{location_text}`](https://github.com/#{repo_handle}/blob/#{commit_sha}/#{path}#L#{failure.line_number})"
    else
      "`#{location_text}`"
    end
  end

  defp format_failure_location(_, _, _), do: nil

  defp truncate_message(message) do
    if String.length(message) > @max_failure_message_length do
      String.slice(message, 0, @max_failure_message_length) <> "…"
    else
      message
    end
  end

  defp get_latest_builds(params) do
    from(b in Builds.Build)
    |> filter_run_report_query(params)
    |> where([b], b.submission_auth != "network_trusted")
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

  defp get_latest_gradle_builds(params) do
    from(b in Gradle.Build)
    |> filter_run_report_query(params)
    |> where([b], b.submission_auth != "network_trusted")
    |> order_by([b], desc: b.inserted_at)
    |> ClickHouseRepo.all()
    |> Enum.filter(&(&1.root_project_name != ""))
    |> Enum.uniq_by(fn build -> {build.root_project_name, Enum.sort(build.requested_tasks)} end)
  end

  # The view reads `test_runs` with `FINAL`, under which ClickHouse uses skip
  # indexes only when `use_skip_indexes_if_final` is on; it's off at the
  # 24.12 compatibility level the server's profile pins, so it's set here.
  # Its exact mode expands the granules the ref and commit SHA indexes select
  # back to whole key ranges, reading the project's whole run history. Exact
  # mode only matters when a run's newest version could stop matching while
  # an older one still does; a run's ref and SHA are only ever filled in,
  # never changed (a shard's report fills a placeholder's blanks), so the
  # version the filter finds is the newest.
  defp get_latest_test_runs(params) do
    from(t in Tests.Test.query())
    |> filter_run_report_query(params)
    |> where([t], t.submission_auth != "network_trusted")
    |> order_by([t], desc: t.inserted_at)
    |> ClickHouseRepo.all(settings: ClickHouseCapabilities.skip_indexes_if_final_settings(ClickHouseRepo))
    |> Enum.group_by(& &1.build_system)
    |> Enum.flat_map(fn
      {"xcode", test_runs} -> latest_test_run_per_scheme(test_runs)
      {_build_system, test_runs} -> latest_commit_test_runs(test_runs)
    end)
  end

  # Expects the test runs newest first. A run without a scheme is kept like any
  # other, under the empty scheme.
  defp latest_test_run_per_scheme(test_runs), do: test_runs |> Enum.uniq_by(& &1.scheme) |> Enum.sort_by(& &1.scheme)

  # Only the build system's latest commit is reported, the way coverage reports
  # a commit, with a rerun replacing the run of the same scheme it repeats.
  defp latest_commit_test_runs([latest | _] = test_runs) do
    test_runs
    |> Enum.filter(&(&1.git_commit_sha == latest.git_commit_sha))
    |> latest_test_run_per_scheme()
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

        "| [#{build.scheme}](#{url}) | #{get_build_status_text(build)} | #{duration} | #{commit_link(build.git_commit_sha, git_remote_url_origin)} |\n"
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

        tasks =
          build.requested_tasks |> Enum.join(" ") |> String.replace("|", "&#124;") |> String.replace(~r/[\r\n]+/, " ")

        "| [#{build.root_project_name}](#{url}) | #{tasks} | #{get_build_status_text(build)} | #{duration} | #{commit_link(build.git_commit_sha, git_remote_url_origin)} |\n"
      end)

    "| Project | Requested tasks | Status | Duration | Commit |\n" <>
      "|:-:|:-:|:-:|:-:|:-:|\n" <>
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
  Looks up a GitHub App installation by `installation_id`.

  `installation_id` is only unique *within* a GitHub instance — two GHES
  instances can each emit installation `123`, and the composite unique
  index on `(client_url, installation_id)` allows that. Pass `:app_id`
  or `:client_url` whenever the caller can disambiguate (webhook
  handlers always can, via `installation.app_id` in the body or the
  `X-GitHub-Hook-Installation-Target-ID` header). Without a
  disambiguator, this falls back to looking up by `installation_id`
  alone, which raises `Ecto.MultipleResultsError` if more than one row
  matches.
  """
  def get_github_app_installation_by_installation_id(installation_id, opts \\ []) do
    query =
      GitHubAppInstallation
      |> where([i], i.installation_id == ^to_string(installation_id))
      |> apply_lookup_opts(opts)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      github_app_installation -> {:ok, github_app_installation}
    end
  end

  defp apply_lookup_opts(query, opts) do
    Enum.reduce(opts, query, fn
      {:client_url, url}, q when is_binary(url) ->
        where(q, [i], i.client_url == ^url)

      {:app_id, app_id}, q when is_binary(app_id) ->
        where(q, [i], i.app_id == ^app_id)

      _, q ->
        q
    end)
  end

  @doc """
  Gets the (single) GitHub app installation for an account, if any.
  """
  def get_github_app_installation_for_account(account_id) do
    case Repo.get_by(GitHubAppInstallation, account_id: account_id) do
      nil -> {:error, :not_found}
      github_app_installation -> {:ok, github_app_installation}
    end
  end

  @doc """
  Gets a GitHub app installation by the manifest-flow App ID Tuist
  recorded when the customer registered an App on their GHES instance.

  Used as a fallback for webhook secret resolution: GHES delivers the
  `installation.created` event before our redirect-driven setup
  callback has filled in `installation_id`, so we have to be able to
  match the inbound webhook to its row by `app_id` too.
  """
  def get_github_app_installation_by_app_id(app_id) do
    case Repo.get_by(GitHubAppInstallation, app_id: to_string(app_id)) do
      nil -> {:error, :not_found}
      github_app_installation -> {:ok, github_app_installation}
    end
  end

  @doc """
  Returns every `GitHubAppInstallation` row that could plausibly own an
  inbound webhook with the given `installation_id` and/or `app_id`.

  Webhook secret resolution uses this list as the candidate set for
  HMAC verification: the schema's composite unique index permits two
  rows to share an `(installation_id, app_id)` pair across different
  `client_url`s, so a single-row lookup can be ambiguous. Iterating
  candidates and picking the one whose `webhook_secret` HMACs the
  inbound body lets the cryptographic check act as the
  disambiguator — only the row whose secret matches GitHub's
  signature is the right row.

  Both filters are optional. Pass `nil` for either to skip it. With
  both `nil`, returns `[]`.

  The result is cached for #{@webhook_installations_cache_ttl_ms} ms
  keyed by `(installation_id, app_id)`. Every inbound webhook hits
  this path before HMAC verification, and the underlying table only
  changes on App install / update / uninstall (rare relative to
  webhook traffic), so memoising the lookup removes one Postgres
  round-trip per webhook on the hot path. The TTL is the sole
  invalidation mechanism: mutations don't bust the cache because
  the only field a stale entry could mis-serve (`webhook_secret`)
  rotates through a flow that takes longer than the TTL anyway.

  ## Opts

  - `:cache` — Cachex instance to use. Defaults to `:tuist`; tests
    pass a per-case Cachex so state doesn't leak across runs.
  """
  def list_github_app_installations_for_webhook(installation_id, app_id, opts \\ []) do
    installation_id = maybe_to_string(installation_id)
    app_id = maybe_to_string(app_id)

    if installation_id == nil and app_id == nil do
      []
    else
      KeyValueStore.get_or_update(
        webhook_installations_cache_key(installation_id, app_id),
        [cache: Keyword.get(opts, :cache, :tuist), ttl: @webhook_installations_cache_ttl_ms],
        fn ->
          case build_webhook_lookup_query(installation_id, app_id) do
            nil -> []
            query -> Repo.all(query)
          end
        end
      )
    end
  end

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value), do: to_string(value)

  defp build_webhook_lookup_query(nil, nil), do: nil

  defp build_webhook_lookup_query(installation_id, nil),
    do: from(i in GitHubAppInstallation, where: i.installation_id == ^installation_id)

  defp build_webhook_lookup_query(nil, app_id), do: from(i in GitHubAppInstallation, where: i.app_id == ^app_id)

  defp build_webhook_lookup_query(installation_id, app_id) do
    from(i in GitHubAppInstallation,
      where: i.installation_id == ^installation_id or i.app_id == ^app_id
    )
  end

  defp webhook_installations_cache_key(installation_id, app_id),
    do: [__MODULE__, :webhook_installations, installation_id || "_", app_id || "_"]

  @doc """
  Updates only an Enterprise installation's API transport endpoint. Changing
  it leaves App credentials, canonical identity, and project connections intact.
  Token and repository cache keys include the installation row and effective
  endpoint. Cached webhook installation lookups refresh within one minute.
  """
  def update_github_app_api_url(%GitHubAppInstallation{} = installation, api_url) do
    installation
    |> GitHubAppInstallation.changeset(%{api_url: api_url})
    |> Repo.update()
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
  Replaces the credentials and pending-install state on an existing
  installation row. Used by the GHES manifest flow when the customer
  re-registers an App on top of a previous, possibly-stale row.
  """
  def replace_github_app_installation(%GitHubAppInstallation{} = github_app_installation, attrs) do
    # The new row supersedes the old one; clear the prior installation_id
    # since the customer has not yet installed the freshly registered App.
    github_app_installation
    |> GitHubAppInstallation.changeset(Map.merge(%{installation_id: nil, html_url: nil}, attrs))
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
  Creates a GitHub app installation or returns the existing installation for the account.
  """
  def create_or_get_github_app_installation(%{installation_id: installation_id, account_id: account_id} = attrs) do
    installation_id = to_string(installation_id)
    attrs = Map.put(attrs, :installation_id, installation_id)

    case Repo.get_by(GitHubAppInstallation, installation_id: installation_id) do
      nil ->
        create_github_app_installation(attrs)

      %GitHubAppInstallation{account_id: ^account_id} = github_app_installation ->
        {:ok, github_app_installation}

      %GitHubAppInstallation{} ->
        {:error, :installation_already_connected}
    end
  end

  @doc """
  Gets repositories for a GitHub app installation.
  """
  def get_github_app_installation_repositories(%GitHubAppInstallation{} = installation) do
    KeyValueStore.get_or_update(
      installation_repositories_cache_key(installation),
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

  defp refresh_github_app_installation_repositories(installation) do
    with {:ok, _repositories} = result <- get_all_repositories_recursively(installation, []) do
      KeyValueStore.put(installation_repositories_cache_key(installation), result, ttl: to_timeout(minute: 15))
      result
    end
  end

  defp installation_repositories_cache_key(installation) do
    [__MODULE__, "repositories", installation.id, installation_api_url(installation), installation.installation_id]
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
  Links a project to a repository its account's GitHub App installation can
  access, storing GitHub's canonical repository name and adopting the
  repository's default branch. Linking a project to the repository it is
  already linked to returns the existing connection.
  """
  def connect_github_repository(%Project{} = project, repository_full_handle, opts \\ [])
      when is_binary(repository_full_handle) do
    case Repo.get_by(VCSConnection, project_id: project.id) do
      nil -> create_github_connection(project, repository_full_handle, Keyword.get(opts, :created_by_id))
      connection -> existing_connection(connection, repository_full_handle)
    end
  end

  @doc """
  The message for a `connect_github_repository/3` error, shared by the API
  and the MCP tool.
  """
  def connect_github_repository_error({:already_connected, %VCSConnection{provider: :origin} = connection}, _handle),
    do:
      "The project is linked to #{connection.repository_full_handle} through Origin. Unlink it from the account's integrations settings before linking a GitHub repository."

  def connect_github_repository_error({:already_connected, connection}, _handle),
    do:
      "The project is already linked to #{connection.repository_full_handle}. Unlink it before linking another repository."

  def connect_github_repository_error(:github_app_not_installed, _handle),
    do: "The account has no GitHub App installation. Install it from the account's integrations settings."

  def connect_github_repository_error(:repository_not_accessible, handle),
    do: "The account's GitHub App installation can't access #{handle}."

  def connect_github_repository_error(:github_unavailable, _handle),
    do: "Tuist couldn't reach GitHub to check the installation's repositories. Try again shortly."

  def connect_github_repository_error(%Ecto.Changeset{}, handle), do: "The project couldn't be linked to #{handle}."

  defp existing_connection(%VCSConnection{provider: :github} = connection, repository_full_handle) do
    if String.downcase(connection.repository_full_handle) == String.downcase(repository_full_handle),
      do: {:ok, connection},
      else: {:error, {:already_connected, connection}}
  end

  defp existing_connection(connection, _repository_full_handle), do: {:error, {:already_connected, connection}}

  defp create_github_connection(project, repository_full_handle, created_by_id) do
    with {:ok, installation} <- installed_github_app(project.account_id),
         {:ok, repository} <- installation_repository(installation, repository_full_handle),
         {:ok, connection} <- insert_github_connection(project, installation, repository, created_by_id) do
      if is_binary(repository.default_branch) and repository.default_branch != "" do
        Projects.update_project(project, %{default_branch: repository.default_branch})
      end

      {:ok, connection}
    end
  end

  # Two first links can both pass the lookup; the one that loses the unique
  # index answers from the link the other created.
  defp insert_github_connection(project, installation, repository, created_by_id) do
    case Projects.create_vcs_connection(%{
           project_id: project.id,
           provider: :github,
           repository_full_handle: repository.full_name,
           created_by_id: created_by_id,
           github_app_installation_id: installation.id
         }) do
      {:ok, connection} ->
        {:ok, connection}

      {:error, %Ecto.Changeset{} = changeset} ->
        with true <- Keyword.has_key?(changeset.errors, :project_id),
             %VCSConnection{} = connection <- Repo.get_by(VCSConnection, project_id: project.id) do
          existing_connection(connection, repository.full_name)
        else
          _ -> {:error, changeset}
        end
    end
  end

  defp installed_github_app(account_id) do
    case get_github_app_installation_for_account(account_id) do
      {:ok, %GitHubAppInstallation{installation_id: installation_id} = installation} when not is_nil(installation_id) ->
        {:ok, installation}

      _ ->
        {:error, :github_app_not_installed}
    end
  end

  # An installation token can read any public repository, so access is checked
  # against the installation's own repositories, as the dashboard does. A cached
  # list that failed or lacks the repository is fetched again, so a repository
  # added to the installation since is found.
  defp installation_repository(installation, repository_full_handle) do
    with {:ok, repositories} <- get_github_app_installation_repositories(installation),
         %{} = repository <- find_repository(repositories, repository_full_handle) do
      {:ok, repository}
    else
      _ ->
        case refresh_github_app_installation_repositories(installation) do
          {:ok, repositories} ->
            case find_repository(repositories, repository_full_handle) do
              nil -> {:error, :repository_not_accessible}
              repository -> {:ok, repository}
            end

          {:error, _reason} ->
            {:error, :github_unavailable}
        end
    end
  end

  defp find_repository(repositories, repository_full_handle) do
    handle = String.downcase(repository_full_handle)
    Enum.find(repositories, &(String.downcase(&1.full_name) == handle))
  end

  @doc """
  Removes a project's link to a GitHub repository.
  """
  def disconnect_github_repository(%Project{} = project) do
    case Repo.get_by(VCSConnection, project_id: project.id, provider: :github) do
      nil -> {:error, :not_found}
      connection -> Projects.delete_vcs_connection(connection)
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
  defaulting to https://github.com. Accepts an optional `:github_app_owner`
  to register the manifest-owned App under a GitHub organization. An optional
  `:api_url` overrides the REST API base URL for GHES server-side calls without
  changing browser navigation or the canonical GitHub instance identity.

  For github.com, returns the direct installation URL of the
  globally-configured Tuist App. For a GHES `client_url`, returns an
  internal route that kicks off the App manifest registration flow —
  GitHub Apps are scoped to a single GitHub instance, so the Tuist
  App registered on github.com cannot be installed on GHES; the customer
  must register and install their own App on the GHES instance and we
  store its credentials per-installation.
  """
  def get_github_app_installation_url(%Account{id: account_id}, opts \\ []) do
    client_url = normalize_client_url(Keyword.get(opts, :client_url))
    github_app_owner = normalize_github_app_owner(Keyword.get(opts, :github_app_owner))
    api_url = if client_url != default_client_url(), do: Keyword.get(opts, :api_url)
    state_token = generate_github_state_token(account_id, client_url, github_app_owner, api_url)

    if client_url == default_client_url() do
      app_name = Environment.github_app_name()
      "#{client_url}/apps/#{app_name}/installations/new?state=#{state_token}"
    else
      Environment.app_url(path: "/integrations/github/manifest/start?state=#{URI.encode_www_form(state_token)}")
    end
  end

  defp normalize_client_url(nil), do: default_client_url()
  defp normalize_client_url(""), do: default_client_url()

  defp normalize_client_url(url) when is_binary(url) do
    url |> String.trim() |> String.trim_trailing("/")
  end

  defp normalize_github_app_owner(nil), do: nil

  defp normalize_github_app_owner(owner) when is_binary(owner) do
    case String.trim(owner) do
      "" -> nil
      owner -> owner
    end
  end

  # GitHub State Token functions

  @doc """
  Generates a signed state token for the given account ID and target GitHub
  client URL. The token round-trips through GitHub's installation flow so we
  know which GitHub instance the resulting installation belongs to.
  """
  def generate_github_state_token(account_id, client_url \\ default_client_url(), github_app_owner \\ nil, api_url \\ nil) do
    api_url = if is_binary(api_url), do: String.trim(api_url), else: api_url
    payload = {account_id, normalize_client_url(client_url), normalize_github_app_owner(github_app_owner)}
    payload = if api_url in [nil, ""], do: payload, else: Tuple.insert_at(payload, 3, api_url)
    Phoenix.Token.sign(Tuist.Web.endpoint(), "github_state", payload)
  end

  @doc """
  Verifies the state token. Returns
  `{:ok, %{account_id: id, client_url: url, github_app_owner: owner, api_url: api_url}}` on
  success, `{:error, reason}` otherwise. Tokens generated before client_url or
  github_app_owner or api_url were introduced are accepted with the available defaults.
  """
  def verify_github_state_token(token) do
    # 90 days
    token_max_age_seconds = 7_776_000

    case Phoenix.Token.verify(
           Tuist.Web.endpoint(),
           "github_state",
           token,
           max_age: token_max_age_seconds
         ) do
      {:ok, payload} ->
        decode_github_state(payload)

      {:error, _reason} = error ->
        error
    end
  end

  defp decode_github_state({account_id, client_url, owner, api_url})
       when is_integer(account_id) and is_binary(client_url) and (is_nil(owner) or is_binary(owner)) do
    case validate_api_url(api_url) do
      {:ok, normalized_api_url} ->
        {:ok,
         %{
           account_id: account_id,
           client_url: normalize_client_url(client_url),
           github_app_owner: normalize_github_app_owner(owner),
           api_url: normalized_api_url
         }}

      {:error, _} ->
        {:error, :invalid}
    end
  end

  defp decode_github_state({account_id, client_url, owner}), do: decode_github_state({account_id, client_url, owner, nil})
  defp decode_github_state({account_id, client_url}), do: decode_github_state({account_id, client_url, nil, nil})

  defp decode_github_state(account_id) when is_integer(account_id),
    do: decode_github_state({account_id, default_client_url(), nil, nil})

  defp decode_github_state(_), do: {:error, :invalid}

  def update_check_run(params), do: Client.update_check_run(params)
end
