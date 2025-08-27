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
        case Agent.test(attrs,
               anthropic_api_key: Environment.anthropic_api_key(),
               openai_api_key: Environment.openai_api_key()
             ) do
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

    brew install cameroncooke/axe/axe --quiet || true
    npm i --location=global appium
    appium driver install xcuitest
    tmux new-session -d -s appium 'appium'
    runner qa --preview-url "#{app_build_url}" --bundle-identifier #{bundle_identifier} --server-url #{server_url} --run-id #{run_id} --auth-token #{auth_token} --account-handle #{account_handle} --project-handle #{project_handle} --prompt "#{prompt}" --anthropic-api-key #{Environment.anthropic_api_key()} --openai-api-key #{Environment.openai_api_key()}
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
  Gets QA runs for a specific project.
  Returns paginated list of QA run structs with preloaded associations.

  ## Options
  - `:limit` - Maximum number of runs to return (default: 50)
  - `:offset` - Number of runs to skip (default: 0)
  - `:preload` - Associations to preload (default: [])
  """
  def qa_runs_for_project(project, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    preload = Keyword.get(opts, :preload, [])

    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        where: pr.project_id == ^project.id,
        order_by: [desc: qa.inserted_at],
        limit: ^limit,
        offset: ^offset,
        preload: ^preload
      )

    Repo.all(query)
  end

  @doc """
  Gets QA runs for a specific project with token usage data.
  Returns paginated list of flattened maps containing run data and token usage totals.

  ## Options
  - `:limit` - Maximum number of runs to return (default: 50)
  - `:offset` - Number of runs to skip (default: 0)
  """
  def qa_runs_with_token_usage_for_project(project, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        where: pr.project_id == ^project.id,
        left_join: tu in TokenUsage,
        on: tu.feature_resource_id == qa.id and tu.feature == "qa",
        group_by: [qa.id, qa.status, qa.inserted_at, qa.prompt, qa.git_ref],
        select: %{
          id: qa.id,
          status: qa.status,
          inserted_at: qa.inserted_at,
          prompt: qa.prompt,
          git_ref: qa.git_ref,
          input_tokens: coalesce(sum(tu.input_tokens), 0),
          output_tokens: coalesce(sum(tu.output_tokens), 0)
        },
        order_by: [desc: qa.inserted_at],
        limit: ^limit,
        offset: ^offset
      )

    Repo.all(query)
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
        "qa_run_update",
        "qa_step_create",
        "qa_step_update",
        "qa_screenshot_create"
      ],
      "project_id" => app_build.preview.project.id
    }

    case Authentication.encode_and_sign(account, claims, token_type: :access, ttl: {1, :hour}) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns QA runs analytics for a given project and time period.
  """
  def qa_runs_analytics(project_id, opts \\ []) do
    {start_date, end_date} = date_range(opts)
    app_name = Keyword.get(opts, :app_name)

    current_count = count_qa_runs(project_id, start_date, end_date, app_name)
    previous_count = count_qa_runs(project_id, Date.add(start_date, -Date.diff(end_date, start_date)), start_date, app_name)

    runs_data = qa_runs_by_day(project_id, start_date, end_date, app_name)

    %{
      trend: calculate_trend(previous_count, current_count),
      count: current_count,
      values: Enum.map(runs_data, & &1.count),
      dates: Enum.map(runs_data, &Date.to_string(&1.date))
    }
  end

  @doc """
  Returns QA issues analytics for a given project and time period.
  """
  def qa_issues_analytics(project_id, opts \\ []) do
    {start_date, end_date} = date_range(opts)
    app_name = Keyword.get(opts, :app_name)

    current_count = count_qa_issues(project_id, start_date, end_date, app_name)
    previous_count = count_qa_issues(project_id, Date.add(start_date, -Date.diff(end_date, start_date)), start_date, app_name)

    issues_data = qa_issues_by_day(project_id, start_date, end_date, app_name)

    %{
      trend: calculate_trend(previous_count, current_count),
      count: current_count,
      values: Enum.map(issues_data, & &1.count),
      dates: Enum.map(issues_data, &Date.to_string(&1.date))
    }
  end

  @doc """
  Returns QA duration analytics for a given project and time period.
  """
  def qa_duration_analytics(project_id, opts \\ []) do
    {start_date, end_date} = date_range(opts)
    app_name = Keyword.get(opts, :app_name)

    current_avg = average_qa_duration(project_id, start_date, end_date, app_name)
    previous_avg = average_qa_duration(project_id, Date.add(start_date, -Date.diff(end_date, start_date)), start_date, app_name)

    duration_data = qa_duration_by_day(project_id, start_date, end_date, app_name)

    %{
      trend: calculate_trend(previous_avg, current_avg),
      total_average_duration: current_avg,
      values: Enum.map(duration_data, & &1.average_duration),
      dates: Enum.map(duration_data, &Date.to_string(&1.date))
    }
  end

  @doc """
  Returns combined QA analytics for a given project.
  """
  def combined_qa_analytics(project_id, opts \\ []) do
    [
      qa_runs_analytics(project_id, opts),
      qa_issues_analytics(project_id, opts),
      qa_duration_analytics(project_id, opts)
    ]
  end

  @doc """
  Returns available apps for analytics filtering.
  """
  def available_apps_for_project(project_id) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        where: pr.project_id == ^project_id,
        distinct: pr.display_name,
        select: pr.display_name,
        order_by: pr.display_name
      )

    apps = Repo.all(query)
    Enum.map(apps, fn app_name -> {app_name, app_name} end)
  end

  defp date_range(opts) do
    start_date = Keyword.get(opts, :start_date, Date.add(Date.utc_today(), -10))
    end_date = Keyword.get(opts, :end_date, Date.utc_today())
    {start_date, end_date}
  end

  defp calculate_trend(previous_value, current_value) do
    case {previous_value, current_value} do
      {0, _} -> 0.0
      {_, 0} -> 0.0
      {prev, curr} -> Float.round(curr / prev * 100, 1) - 100.0
    end
  end

  defp count_qa_runs(project_id, start_date, end_date, app_name) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        where:
          pr.project_id == ^project_id and
            qa.inserted_at >= ^DateTime.new!(start_date, ~T[00:00:00]) and
            qa.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]),
        select: count(qa.id)
      )

    query = apply_app_filter(query, app_name, [:qa, :ab, :pr])
    Repo.one(query) || 0
  end

  defp count_qa_issues(project_id, start_date, end_date, app_name) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        join: step in assoc(qa, :run_steps),
        where:
          pr.project_id == ^project_id and
            qa.inserted_at >= ^DateTime.new!(start_date, ~T[00:00:00]) and
            qa.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
            fragment("array_length(?, 1)", step.issues) > 0,
        select: fragment("SUM(array_length(?, 1))", step.issues)
      )

    query = apply_app_filter(query, app_name, [:qa, :ab, :pr, :step])
    Repo.one(query) || 0
  end

  defp average_qa_duration(project_id, start_date, end_date, app_name) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        where:
          pr.project_id == ^project_id and
            qa.inserted_at >= ^DateTime.new!(start_date, ~T[00:00:00]) and
            qa.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
            qa.status in ["completed", "failed"] and
            not is_nil(qa.finished_at),
        select:
          fragment(
            "ABS(EXTRACT(EPOCH FROM (? - ?))) * 1000",
            qa.finished_at,
            qa.inserted_at
          )
      )

    query = apply_app_filter(query, app_name, [:qa, :ab, :pr])
    durations = Repo.all(query)

    if Enum.empty?(durations) do
      0
    else
      durations
      |> Enum.map(&Decimal.to_float/1)
      |> Enum.sum()
      |> Kernel./(length(durations))
      |> trunc()
    end
  end

  defp qa_runs_by_day(project_id, start_date, end_date, app_name) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        where:
          pr.project_id == ^project_id and
            qa.inserted_at >= ^DateTime.new!(start_date, ~T[00:00:00]) and
            qa.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]),
        group_by: fragment("DATE(?)", qa.inserted_at),
        select: %{
          date: fragment("DATE(?)", qa.inserted_at),
          count: count(qa.id)
        },
        order_by: [asc: fragment("DATE(?)", qa.inserted_at)]
      )

    query = apply_app_filter(query, app_name, [:qa, :ab, :pr])
    results = Repo.all(query)
    results_map = Map.new(results, fn result -> {result.date, result.count} end)

    # Fill in missing days with zero counts
    start_date
    |> Date.range(end_date)
    |> Enum.map(fn date ->
      count = Map.get(results_map, date, 0)
      %{date: date, count: count}
    end)
  end

  defp qa_duration_by_day(project_id, start_date, end_date, app_name) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        where:
          pr.project_id == ^project_id and
            qa.inserted_at >= ^DateTime.new!(start_date, ~T[00:00:00]) and
            qa.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
            qa.status in ["completed", "failed"] and
            not is_nil(qa.finished_at),
        group_by: fragment("DATE(?)", qa.inserted_at),
        select: %{
          date: fragment("DATE(?)", qa.inserted_at),
          average_duration: fragment("AVG(EXTRACT(EPOCH FROM (? - ?)) * 1000)", qa.finished_at, qa.inserted_at)
        },
        order_by: [asc: fragment("DATE(?)", qa.inserted_at)]
      )

    query = apply_app_filter(query, app_name, [:qa, :ab, :pr])
    results = Repo.all(query)
    results_map = Map.new(results, fn result ->
      value = case result.average_duration do
        nil -> 0
        %Decimal{} = avg -> Decimal.to_float(avg)
        avg when is_float(avg) -> avg
        _ -> 0
      end
      {result.date, value}
    end)

    # Fill in missing days with zero averages
    start_date
    |> Date.range(end_date)
    |> Enum.map(fn date ->
      value = Map.get(results_map, date, 0)
      %{date: date, average_duration: value}
    end)
  end

  defp qa_issues_by_day(project_id, start_date, end_date, app_name) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        join: step in assoc(qa, :run_steps),
        where:
          pr.project_id == ^project_id and
            qa.inserted_at >= ^DateTime.new!(start_date, ~T[00:00:00]) and
            qa.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
            fragment("array_length(?, 1)", step.issues) > 0,
        group_by: fragment("DATE(?)", qa.inserted_at),
        select: %{
          date: fragment("DATE(?)", qa.inserted_at),
          count: fragment("SUM(array_length(?, 1))", step.issues)
        },
        order_by: [asc: fragment("DATE(?)", qa.inserted_at)]
      )

    query = apply_app_filter(query, app_name, [:qa, :ab, :pr, :step])
    results = Repo.all(query)
    results_map = Map.new(results, fn result -> {result.date, result.count} end)

    # Fill in missing days with zero counts
    start_date
    |> Date.range(end_date)
    |> Enum.map(fn date ->
      count = Map.get(results_map, date, 0)
      %{date: date, count: count}
    end)
  end

  defp apply_app_filter(query, nil, _bindings), do: query
  defp apply_app_filter(query, "any", _bindings), do: query
  defp apply_app_filter(query, app_name, [:qa, :ab, :pr]), do: where(query, [qa, ab, pr], pr.display_name == ^app_name)
  defp apply_app_filter(query, app_name, [:qa, :ab, :pr, :step]), do: where(query, [qa, ab, pr, step], pr.display_name == ^app_name)
end
