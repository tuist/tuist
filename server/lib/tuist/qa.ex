defmodule Tuist.QA do
  @moduledoc """
  QA module for interacting with Tuist QA.
  """

  import Ecto.Query

  alias Runner.QA.Agent
  alias Tuist.Accounts
  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.AppBuild
  alias Tuist.Authentication
  alias Tuist.Billing.TokenUsage
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.Namespace
  alias Tuist.Projects
  alias Tuist.QA.Log
  alias Tuist.QA.Run
  alias Tuist.QA.Screenshot
  alias Tuist.QA.Step
  alias Tuist.Repo
  alias Tuist.SSHClient
  alias Tuist.Storage
  alias Tuist.VCS

  require EEx

  @qa_summary_template_path Path.join([__DIR__, "qa", "qa_test_summary.eex"])
  EEx.function_from_file(:defp, :render_qa_summary, @qa_summary_template_path, [:assigns])

  @doc """
  Run a QA test run for the given app build.
  """
  def test(%{app_build: %AppBuild{id: app_build_id} = app_build, prompt: prompt} = params) do
    app_build = Repo.preload(app_build, preview: [project: :account])
    issue_comment_id = Map.get(params, :issue_comment_id)

    with {:ok, qa_run} <-
           create_qa_run(%{
             app_build_id: app_build_id,
             prompt: prompt,
             status: "pending",
             issue_comment_id: issue_comment_id,
             git_ref: app_build.preview.git_ref,
             vcs_provider: app_build.preview.project.vcs_provider,
             vcs_repository_full_handle: app_build.preview.project.vcs_repository_full_handle
           }),
         app_build_url = generate_app_build_download_url(app_build),
         {:ok, auth_token} <- create_qa_auth_token(app_build) do
      attrs = %{
        preview_url: app_build_url,
        bundle_identifier: app_build.preview.bundle_identifier,
        prompt: prompt,
        server_url: Environment.app_url(),
        run_id: qa_run.id,
        auth_token: auth_token,
        account_handle: app_build.preview.project.account.name,
        project_handle: app_build.preview.project.name
      }

      if Environment.namespace_enabled?() do
        with :ok <- run_qa_tests_in_namespace(attrs, app_build.preview.project.account) do
          qa_run(qa_run.id)
        end
      else
        case Agent.test(attrs, anthropic_api_key: Environment.anthropic_api_key()) do
          :ok ->
            qa_run(qa_run.id)

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  defp account_initializing_namespace_tenant_if_absent(account) do
    if is_nil(account.namespace_tenant_id) do
      Accounts.create_namespace_tenant_for_account(account)
    else
      {:ok, account}
    end
  end

  defp run_qa_tests_in_namespace(attrs, account) do
    with {:ok, account_with_tenant} <- account_initializing_namespace_tenant_if_absent(account),
         {:ok, %{ssh_connection: ssh_connection, instance: instance, tenant_token: tenant_token}} <-
           Namespace.create_instance_with_ssh_connection(account_with_tenant.namespace_tenant_id) do
      run_qa_tests_in_namespace_instance(attrs, instance, ssh_connection, tenant_token)
    end
  end

  defp run_qa_tests_in_namespace_instance(attrs, instance, ssh_connection, tenant_token) do
    with :ok <-
           SSHClient.transfer_file(
             ssh_connection,
             "/app/bin/runner",
             "/usr/local/bin/runner",
             permissions: 0o100755
           ),
         {:ok, _output} <- SSHClient.run_command(ssh_connection, qa_script(attrs)) do
      :ok
    end
  after
    Namespace.destroy_instance(instance.id, tenant_token)
  end

  defp qa_script(%{
         preview_url: app_build_url,
         bundle_identifier: bundle_identifier,
         prompt: prompt,
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    """
    set -e

    brew install facebook/fb/idb-companion cameroncooke/axe/axe pipx --quiet || true
    pipx install fb-idb
    export PATH=$PATH:$HOME/.local/bin
    runner qa --preview-url "#{app_build_url}" --bundle-identifier #{bundle_identifier} --server-url #{server_url} --run-id #{run_id} --auth-token #{auth_token} --account-handle #{account_handle} --project-handle #{project_handle} --prompt "#{prompt}" --anthropic-api-key #{Environment.anthropic_api_key()}
    """
  end

  @doc """
  Creates a new QA run.
  """
  def create_qa_run(attrs) do
    %Run{}
    |> Run.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a QA run.
  """
  def update_qa_run(%Run{} = qa_run, attrs) do
    qa_run
    |> Run.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a new QA run step.
  """
  def create_qa_step(attrs) do
    %Step{}
    |> Step.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a QA step by ID.
  """
  def step(id) do
    case Repo.get(Step, id) do
      nil -> {:error, :not_found}
      step -> {:ok, step}
    end
  end

  @doc """
  Updates a QA step.
  """
  def update_step(%Step{} = step, attrs) do
    step
    |> Step.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets a QA run by ID.
  """
  def qa_run(id, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    case Run |> Repo.get(id) |> Repo.preload(preload) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end

  @doc """
  Gets a QA run by ID with project and account information for ops interface.
  Returns a map with the necessary fields for display.
  """
  def qa_run_for_ops(qa_run_id) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        join: p in assoc(pr, :project),
        join: a in assoc(p, :account),
        where: qa.id == ^qa_run_id,
        select: %{
          id: qa.id,
          project_name: p.name,
          account_name: a.name,
          status: qa.status,
          inserted_at: qa.inserted_at,
          prompt: qa.prompt
        }
      )

    Repo.one(query)
  end

  @doc """
  Gets QA logs for a given QA run ID from ClickHouse.
  """
  def logs_for_run(qa_run_id) do
    query =
      from(log in Log,
        where: log.qa_run_id == ^qa_run_id,
        order_by: [asc: log.timestamp]
      )

    logs = ClickHouseRepo.all(query)

    Enum.map(logs, &Log.normalize_enums/1)
  end

  @doc """
  Gets QA screenshots for a given QA run ID.
  """
  def screenshots_for_run(qa_run_id) do
    query =
      from(screenshot in Screenshot,
        where: screenshot.qa_run_id == ^qa_run_id,
        order_by: [asc: screenshot.inserted_at]
      )

    Repo.all(query)
  end

  @doc """
  Gets QA runs chart data for the last 30 days.
  Returns a list of [date, count] pairs for each day.
  """
  def qa_runs_chart_data do
    thirty_days_ago = Date.add(Date.utc_today(), -30)
    thirty_days_ago_datetime = DateTime.new!(thirty_days_ago, ~T[00:00:00], "Etc/UTC")

    query =
      from(qa in Run,
        where: qa.inserted_at >= ^thirty_days_ago_datetime,
        group_by: fragment("DATE(?)", qa.inserted_at),
        select: %{
          date: fragment("DATE(?)", qa.inserted_at),
          count: count(qa.id)
        },
        order_by: [asc: fragment("DATE(?)", qa.inserted_at)]
      )

    results = Repo.all(query)
    results_map = Map.new(results, fn result -> {result.date, result.count} end)

    date_range = Date.range(thirty_days_ago, Date.utc_today())

    Enum.map(date_range, fn date ->
      count = Map.get(results_map, date, 0)
      [Date.to_string(date), count]
    end)
  end

  @doc """
  Gets cumulative projects usage chart data for the last 30 days.
  Returns a list of [date, cumulative_unique_projects_count] pairs.
  """
  def projects_usage_chart_data do
    thirty_days_ago = Date.add(Date.utc_today(), -30)
    thirty_days_ago_datetime = DateTime.new!(thirty_days_ago, ~T[00:00:00], "Etc/UTC")

    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        join: p in assoc(pr, :project),
        where: qa.inserted_at >= ^thirty_days_ago_datetime,
        group_by: fragment("DATE(?)", qa.inserted_at),
        select: %{
          date: fragment("DATE(?)", qa.inserted_at),
          project_ids: fragment("array_agg(DISTINCT ?)", p.id)
        },
        order_by: [asc: fragment("DATE(?)", qa.inserted_at)]
      )

    results_by_date =
      query
      |> Repo.all()
      |> Map.new(fn r -> {r.date, MapSet.new(r.project_ids)} end)

    date_range = Date.range(thirty_days_ago, Date.utc_today())

    {_, acc} =
      Enum.reduce(date_range, {MapSet.new(), []}, fn date, {cumulative, out} ->
        todays_projects = Map.get(results_by_date, date, MapSet.new())
        cumulative = MapSet.union(cumulative, todays_projects)
        {cumulative, [[Date.to_string(date), MapSet.size(cumulative)] | out]}
      end)

    Enum.reverse(acc)
  end

  @doc """
  Gets recent QA runs for ops interface.
  Returns up to 50 most recent runs with project and account info.
  """
  def recent_qa_runs do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        join: p in assoc(pr, :project),
        join: a in assoc(p, :account),
        left_join: tu in TokenUsage,
        on: tu.feature_resource_id == qa.id and tu.feature == "qa",
        group_by: [qa.id, p.name, a.name, qa.status, qa.inserted_at, qa.prompt],
        select: %{
          id: qa.id,
          project_name: p.name,
          account_name: a.name,
          status: qa.status,
          inserted_at: qa.inserted_at,
          prompt: qa.prompt,
          input_tokens: coalesce(sum(tu.input_tokens), 0),
          output_tokens: coalesce(sum(tu.output_tokens), 0)
        },
        order_by: [desc: qa.inserted_at],
        limit: 50
      )

    Repo.all(query)
  end

  @doc """
  Creates a new QA screenshot.
  """
  def create_qa_screenshot(attrs) do
    %Screenshot{}
    |> Screenshot.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a screenshot by ID and optionally by QA run ID.
  """
  def screenshot(screenshot_id, opts \\ []) do
    qa_run_id = Keyword.get(opts, :qa_run_id)

    screenshot =
      if qa_run_id do
        Repo.one(from(s in Screenshot, where: s.id == ^screenshot_id and s.qa_run_id == ^qa_run_id))
      else
        Repo.get(Screenshot, screenshot_id)
      end

    case screenshot do
      nil -> {:error, :not_found}
      screenshot -> {:ok, screenshot}
    end
  end

  @doc """
  Updates screenshots to associate them with a QA run step.
  """
  def update_screenshots_with_step_id(qa_run_id, qa_step_id) do
    Repo.update_all(
      from(s in Screenshot, where: s.qa_run_id == ^qa_run_id and is_nil(s.qa_step_id)),
      set: [qa_step_id: qa_step_id]
    )
  end

  @doc """
  Generates a storage key for a QA screenshot.
  """
  def screenshot_storage_key(%{
        account_handle: account_handle,
        project_handle: project_handle,
        qa_run_id: qa_run_id,
        screenshot_id: screenshot_id
      }) do
    "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/qa/screenshots/#{qa_run_id}/#{screenshot_id}.png"
  end

  @doc """
  Finds pending QA runs for the given app build.

  Returns a list of pending QA runs that match the app build's repository URL
  and git_ref, and have no app_build_id assigned yet.
  """
  def find_pending_qa_runs_for_app_build(app_build) do
    app_build = Repo.preload(app_build, preview: [project: :account])
    project = app_build.preview.project
    preview = app_build.preview

    if project.vcs_repository_full_handle && project.vcs_provider && preview.git_ref do
      Repo.all(
        from(run in Run,
          where:
            is_nil(run.app_build_id) and run.status == "pending" and
              run.vcs_repository_full_handle == ^project.vcs_repository_full_handle and
              run.vcs_provider == ^project.vcs_provider and
              run.git_ref == ^preview.git_ref
        )
      )
    else
      []
    end
  end

  @doc """
  Posts a QA test summary comment to VCS for the given QA run.
  """
  def post_vcs_test_summary(qa_run) do
    qa_run =
      Repo.preload(qa_run,
        app_build: [preview: [project: :account]],
        run_steps: :screenshot
      )

    preview = qa_run.app_build.preview
    project = preview.project
    comment_body = render_qa_summary_comment_body(qa_run, project)

    if qa_run.issue_comment_id do
      VCS.update_comment(%{
        repository_full_handle: project.vcs_repository_full_handle,
        comment_id: qa_run.issue_comment_id,
        body: comment_body,
        project: project
      })
    else
      VCS.create_comment(%{
        repository_full_handle: project.vcs_repository_full_handle,
        git_ref: preview.git_ref,
        body: comment_body,
        project: project
      })
    end
  end

  defp render_qa_summary_comment_body(qa_run, project) do
    preview = qa_run.app_build.preview

    preview_url =
      "#{Environment.app_url()}/#{project.account.name}/#{project.name}/previews/#{preview.id}"

    render_qa_summary(%{
      run_steps: Enum.sort_by(qa_run.run_steps, & &1.inserted_at, DateTime),
      issue_count: qa_run.run_steps |> Enum.flat_map(& &1.issues) |> Enum.count(),
      app_url: Environment.app_url(),
      account_handle: project.account.name,
      project_handle: project.name,
      qa_run_id: qa_run.id,
      prompt: qa_run.prompt,
      preview_url: preview_url,
      preview_display_name: preview.display_name,
      commit_sha: preview.git_commit_sha,
      git_remote_url_origin: Projects.get_repository_url(project)
    })
  end

  defp generate_app_build_download_url(%AppBuild{} = app_build) do
    storage_key =
      AppBuilds.storage_key(%{
        account_handle: app_build.preview.project.account.name,
        project_handle: app_build.preview.project.name,
        app_build_id: app_build.id
      })

    Storage.generate_download_url(storage_key)
  end

  defp create_qa_auth_token(%AppBuild{} = app_build) do
    account = app_build.preview.project.account

    claims = %{
      "type" => "account",
      "scopes" => [
        "project_qa_run_update",
        "project_qa_step_create",
        "project_qa_step_update",
        "project_qa_screenshot_create"
      ],
      "project_id" => app_build.preview.project.id
    }

    case Authentication.encode_and_sign(account, claims, token_type: :access, ttl: {1, :hour}) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end
end
