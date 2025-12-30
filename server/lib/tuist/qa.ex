defmodule Tuist.QA do
  @moduledoc """
  QA module for interacting with Tuist QA.
  """

  import Ecto.Query

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Message
  alias LangChain.Message.ContentPart
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
  alias Tuist.QA.LaunchArgumentGroup
  alias Tuist.QA.Log
  alias Tuist.QA.Recording
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
  Run a QA test run for the given QA run.
  """
  def test(%Run{} = qa_run) do
    qa_run = Repo.preload(qa_run, app_build: [preview: [project: :account]])
    app_build = qa_run.app_build

    launch_argument_groups = select_launch_argument_groups(qa_run.prompt, app_build.preview.project)

    {:ok, qa_run} =
      update_qa_run(qa_run, %{
        launch_argument_groups:
          Enum.map(launch_argument_groups, fn group ->
            %{
              "name" => group.name,
              "description" => group.description,
              "value" => group.value
            }
          end),
        app_description: app_build.preview.project.qa_app_description,
        email: app_build.preview.project.qa_email,
        password: app_build.preview.project.qa_password
      })

    app_build_url = generate_app_build_download_url(app_build)

    with {:ok, auth_token} <- create_qa_auth_token(app_build) do
      attrs = %{
        preview_url: app_build_url,
        bundle_identifier: app_build.preview.bundle_identifier,
        prompt: qa_run.prompt,
        launch_arguments: Enum.map_join(launch_argument_groups, " ", & &1.value),
        server_url: Environment.app_url(),
        run_id: qa_run.id,
        auth_token: auth_token,
        account_handle: app_build.preview.project.account.name,
        project_handle: app_build.preview.project.name,
        app_description: app_build.preview.project.qa_app_description,
        email: app_build.preview.project.qa_email,
        password: app_build.preview.project.qa_password
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
         launch_arguments: launch_arguments,
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle,
         app_description: app_description,
         email: email,
         password: password
       }) do
    """
    set -e

    brew install cameroncooke/axe/axe --quiet || true
    brew install ffmpeg
    npm i --location=global appium
    appium driver install xcuitest
    tmux new-session -d -s appium 'appium'
    runner qa --preview-url "#{app_build_url}" --bundle-identifier #{bundle_identifier} --server-url #{server_url} --run-id #{run_id} --auth-token #{auth_token} --account-handle #{account_handle} --project-handle #{project_handle} --prompt "#{prompt}" --launch-arguments "\\"#{launch_arguments}\\"" --app-description "#{app_description}" --email "#{email}" --password "#{password}" --anthropic-api-key #{Environment.anthropic_api_key()} --openai-api-key #{Environment.openai_api_key()}
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
  Creates a new QA recording.
  """
  def create_qa_recording(attrs) do
    %Recording{}
    |> Recording.create_changeset(attrs)
    |> Repo.insert()
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
  Creates a new launch argument group.
  """
  def create_launch_argument_group(attrs) do
    %LaunchArgumentGroup{}
    |> LaunchArgumentGroup.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a launch argument group.
  """
  def update_launch_argument_group(%LaunchArgumentGroup{} = launch_argument_group, attrs) do
    launch_argument_group
    |> LaunchArgumentGroup.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a launch argument group.
  """
  def delete_launch_argument_group(%LaunchArgumentGroup{} = launch_argument_group) do
    Repo.delete(launch_argument_group)
  end

  @doc """
  Gets a launch argument group by ID.
  """
  def get_launch_argument_group(id) do
    case Repo.get(LaunchArgumentGroup, id) do
      nil -> {:error, :not_found}
      launch_argument_group -> {:ok, launch_argument_group}
    end
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

    case Repo.get(Run, id) do
      nil -> {:error, :not_found}
      qa_run -> {:ok, Repo.preload(qa_run, preload)}
    end
  end

  @doc """
  Lists QA runs for a specific project with Flop pagination.
  """
  def list_qa_runs_for_project(project, options \\ %{}, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    base_query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        where: pr.project_id == ^project.id,
        preload: ^preload
      )

    Flop.validate_and_run!(base_query, options, for: Run)
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
    "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/qa/#{qa_run_id}/screenshots/#{screenshot_id}.png"
  end

  @doc """
  Generates a storage key for a QA recording.
  """
  def recording_storage_key(%{account_handle: account_handle, project_handle: project_handle, qa_run_id: qa_run_id}) do
    "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/qa/#{qa_run_id}/recording.mp4"
  end

  @doc """
  Finds pending QA runs for the given app build.

  Returns a list of pending QA runs that match the app build's repository URL
  and git_ref, and have no app_build_id assigned yet.
  """
  def find_pending_qa_runs_for_app_build(app_build) do
    app_build = Repo.preload(app_build, preview: [project: [:account, :vcs_connection]])
    preview = app_build.preview

    if preview.git_ref do
      Repo.all(
        from(run in Run,
          where:
            is_nil(run.app_build_id) and run.status == "pending" and
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
        app_build: [preview: [project: [:account, :vcs_connection]]],
        run_steps: :screenshot
      )

    preview = qa_run.app_build.preview
    project = preview.project
    comment_body = render_qa_summary_comment_body(qa_run, project)

    if project.vcs_connection do
      if qa_run.issue_comment_id do
        VCS.update_comment(%{
          repository_full_handle: project.vcs_connection.repository_full_handle,
          comment_id: qa_run.issue_comment_id,
          body: comment_body,
          project: project
        })
      else
        VCS.create_comment(%{
          repository_full_handle: project.vcs_connection.repository_full_handle,
          git_ref: preview.git_ref,
          body: comment_body,
          project: project
        })
      end
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

    Storage.generate_download_url(storage_key, app_build.preview.project.account)
  end

  defp create_qa_auth_token(%AppBuild{} = app_build) do
    account = app_build.preview.project.account

    claims = %{
      "type" => "account",
      "scopes" => [
        "project:qa_run:update",
        "project:qa_step:create",
        "project:qa_step:update",
        "project:qa_screenshot:create"
      ],
      "project_id" => app_build.preview.project.id
    }

    case Authentication.encode_and_sign(account, claims, token_type: :access, ttl: {1, :hour}) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp select_launch_argument_groups(prompt, project) do
    project = Repo.preload(project, :qa_launch_argument_groups)

    case project.qa_launch_argument_groups do
      [] ->
        []

      launch_argument_groups ->
        system_prompt = """
        Given a test prompt and a list of available launch argument groups, determine which groups should be used.

        Available launch argument groups:
        #{Enum.map_join(launch_argument_groups, "\n", fn group -> "- Name: #{group.name}, Description: #{group.description}, Arguments: #{group.value}" end)}

        Analyze the user's prompt and respond with ONLY the launch argument group names that should be used.
        Unless prompt mentions the log in flow or a signed out user, include launch argument groups to automatically log in when available.
        If multiple groups should be used, delimit them with a comma.
        If no groups match, respond with an empty string.
        Do not include any explanation, just the launch arguments.
        """

        user_message = "Test prompt: #{prompt}"

        llm =
          ChatAnthropic.new!(%{
            model: "claude-sonnet-4-20250514",
            api_key: Environment.anthropic_api_key()
          })

        chain =
          %{llm: llm}
          |> LLMChain.new!()
          |> LLMChain.add_messages([
            Message.new_system!(system_prompt),
            Message.new_user!(user_message)
          ])

        chain
        |> LLMChain.run(
          with_fallbacks: [
            ChatOpenAI.new!(%{
              model: "gpt-5",
              max_completion_tokens: 2000,
              api_key: Environment.openai_api_key()
            })
          ]
        )
        |> process_llm_launch_argument_groups_result(launch_argument_groups)
    end
  end

  defp process_llm_launch_argument_groups_result(
         {:ok, %LLMChain{last_message: %{content: [%ContentPart{content: content}]}}},
         launch_argument_groups
       ) do
    content
    |> String.trim()
    |> String.split(",")
    |> Enum.map(fn group_name ->
      Enum.find(launch_argument_groups, fn group ->
        group.name == String.trim(group_name)
      end)
    end)
    |> Enum.filter(& &1)
  end

  defp process_llm_launch_argument_groups_result({:ok, %LLMChain{last_message: %{content: []}}}, _launch_argument_groups) do
    []
  end

  @doc """
  Returns QA runs analytics for a given project and time period.
  """
  def qa_runs_analytics(project_id, opts \\ []) do
    {start_datetime, end_datetime} = datetime_range(opts)
    app_name = Keyword.get(opts, :app_name)
    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime, end_datetime)

    current_count = count_qa_runs(project_id, start_datetime, end_datetime, app_name)

    previous_count =
      count_qa_runs(
        project_id,
        DateTime.add(start_datetime, -days_delta, :day),
        start_datetime,
        app_name
      )

    runs_data = qa_runs_by_period(project_id, start_datetime, end_datetime, app_name, date_period)

    %{
      trend: calculate_trend(previous_count, current_count),
      count: current_count,
      values: Enum.map(runs_data, & &1.count),
      dates: Enum.map(runs_data, & &1.date)
    }
  end

  @doc """
  Returns QA issues analytics for a given project and time period.
  """
  def qa_issues_analytics(project_id, opts \\ []) do
    {start_datetime, end_datetime} = datetime_range(opts)
    app_name = Keyword.get(opts, :app_name)
    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime, end_datetime)

    current_count = count_qa_issues(project_id, start_datetime, end_datetime, app_name)

    previous_count =
      count_qa_issues(
        project_id,
        DateTime.add(start_datetime, -days_delta, :day),
        start_datetime,
        app_name
      )

    issues_data = qa_issues_by_period(project_id, start_datetime, end_datetime, app_name, date_period)

    %{
      trend: calculate_trend(previous_count, current_count),
      count: current_count,
      values: Enum.map(issues_data, & &1.count),
      dates: Enum.map(issues_data, & &1.date)
    }
  end

  @doc """
  Returns QA duration analytics for a given project and time period.
  """
  def qa_duration_analytics(project_id, opts \\ []) do
    {start_datetime, end_datetime} = datetime_range(opts)
    app_name = Keyword.get(opts, :app_name)
    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime, end_datetime)

    current_avg = average_qa_duration(project_id, start_datetime, end_datetime, app_name)

    previous_avg =
      average_qa_duration(
        project_id,
        DateTime.add(start_datetime, -days_delta, :day),
        start_datetime,
        app_name
      )

    duration_data = qa_duration_by_period(project_id, start_datetime, end_datetime, app_name, date_period)

    %{
      trend: calculate_trend(previous_avg, current_avg),
      total_average_duration: current_avg,
      values: Enum.map(duration_data, & &1.average_duration),
      dates: Enum.map(duration_data, & &1.date)
    }
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
        distinct: pr.bundle_identifier,
        select: {pr.bundle_identifier, pr.display_name},
        order_by: pr.display_name
      )

    Repo.all(query)
  end

  defp datetime_range(opts) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -10, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    {start_datetime, end_datetime}
  end

  defp date_period(start_datetime, end_datetime) do
    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))

    cond do
      days_delta <= 1 -> :hour
      days_delta <= 90 -> :day
      true -> :month
    end
  end

  defp date_range_for_date_period(:hour, start_datetime, end_datetime) do
    start_datetime = DateTime.truncate(start_datetime, :second)
    end_datetime = DateTime.truncate(end_datetime, :second)

    start_datetime
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, end_datetime) != :gt))
  end

  defp date_range_for_date_period(:month, start_datetime, end_datetime) do
    start_datetime
    |> DateTime.to_date()
    |> Date.beginning_of_month()
    |> Date.range(Date.beginning_of_month(DateTime.to_date(end_datetime)))
    |> Enum.filter(&(&1.day == 1))
  end

  defp date_range_for_date_period(:day, start_datetime, end_datetime) do
    start_datetime
    |> DateTime.to_date()
    |> Date.range(DateTime.to_date(end_datetime))
    |> Enum.to_list()
  end

  defp normalise_date(date_input, :hour) do
    case date_input do
      %DateTime{} = dt ->
        Calendar.strftime(dt, "%Y-%m-%d %H:00")

      %NaiveDateTime{} = dt ->
        Calendar.strftime(dt, "%Y-%m-%d %H:00")

      %Date{} = d ->
        Date.to_string(d) <> " 00:00"
    end
  end

  defp normalise_date(date_input, date_period) do
    date =
      case date_input do
        %DateTime{} = dt -> DateTime.to_date(dt)
        %NaiveDateTime{} = dt -> NaiveDateTime.to_date(dt)
        %Date{} = d -> d
      end

    case date_period do
      :day -> Date.to_string(date)
      :month -> Date.to_string(Date.beginning_of_month(date))
    end
  end

  defp calculate_trend(previous_value, current_value) do
    case {previous_value, current_value} do
      {0, _} -> 0.0
      {_, 0} -> 0.0
      {prev, curr} -> Float.round(curr / prev * 100, 1) - 100.0
    end
  end

  defp count_qa_runs(project_id, start_datetime, end_datetime, app_name) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        where:
          pr.project_id == ^project_id and
            qa.inserted_at >= ^start_datetime and
            qa.inserted_at < ^end_datetime,
        select: count(qa.id)
      )

    query = apply_app_filter(query, app_name, [:qa, :ab, :pr])
    Repo.one(query) || 0
  end

  defp count_qa_issues(project_id, start_datetime, end_datetime, app_name) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        join: step in assoc(qa, :run_steps),
        where:
          pr.project_id == ^project_id and
            qa.inserted_at >= ^start_datetime and
            qa.inserted_at < ^end_datetime and
            fragment("array_length(?, 1)", step.issues) > 0,
        select: fragment("SUM(array_length(?, 1))", step.issues)
      )

    query = apply_app_filter(query, app_name, [:qa, :ab, :pr, :step])
    Repo.one(query) || 0
  end

  defp average_qa_duration(project_id, start_datetime, end_datetime, app_name) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        where:
          pr.project_id == ^project_id and
            qa.inserted_at >= ^start_datetime and
            qa.inserted_at < ^end_datetime and
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

  defp qa_runs_by_period(project_id, start_datetime, end_datetime, app_name, date_period) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        where:
          pr.project_id == ^project_id and
            qa.inserted_at >= ^start_datetime and
            qa.inserted_at < ^end_datetime
      )

    query =
      query
      |> add_date_grouping(date_period)
      |> apply_app_filter(app_name, [:qa, :ab, :pr])

    results = Repo.all(query)
    results_map = Map.new(results, fn result -> {normalise_date(result.date, date_period), result.count} end)

    date_period
    |> date_range_for_date_period(start_datetime, end_datetime)
    |> Enum.map(fn date ->
      key = normalise_date(date, date_period)
      count = Map.get(results_map, key, 0)
      %{date: key, count: count}
    end)
  end

  defp add_date_grouping(query, :hour) do
    from(qa in query,
      group_by: fragment("date_trunc('hour', ?)", qa.inserted_at),
      select: %{
        date: fragment("date_trunc('hour', ?)", qa.inserted_at),
        count: count(qa.id)
      },
      order_by: [asc: fragment("date_trunc('hour', ?)", qa.inserted_at)]
    )
  end

  defp add_date_grouping(query, :day) do
    from(qa in query,
      group_by: fragment("DATE(?)", qa.inserted_at),
      select: %{
        date: fragment("DATE(?)", qa.inserted_at),
        count: count(qa.id)
      },
      order_by: [asc: fragment("DATE(?)", qa.inserted_at)]
    )
  end

  defp add_date_grouping(query, :month) do
    from(qa in query,
      group_by: fragment("date_trunc('month', ?)", qa.inserted_at),
      select: %{
        date: fragment("date_trunc('month', ?)", qa.inserted_at),
        count: count(qa.id)
      },
      order_by: [asc: fragment("date_trunc('month', ?)", qa.inserted_at)]
    )
  end

  defp qa_duration_by_period(project_id, start_datetime, end_datetime, app_name, date_period) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        where:
          pr.project_id == ^project_id and
            qa.inserted_at >= ^start_datetime and
            qa.inserted_at < ^end_datetime and
            qa.status in ["completed", "failed"] and
            not is_nil(qa.finished_at)
      )

    query =
      query
      |> add_duration_date_grouping(date_period)
      |> apply_app_filter(app_name, [:qa, :ab, :pr])

    results = Repo.all(query)

    results_map =
      Map.new(results, fn result ->
        value =
          case result.average_duration do
            nil -> 0
            %Decimal{} = avg -> Decimal.to_float(avg)
            avg when is_float(avg) -> avg
            _ -> 0
          end

        {normalise_date(result.date, date_period), value}
      end)

    date_period
    |> date_range_for_date_period(start_datetime, end_datetime)
    |> Enum.map(fn date ->
      key = normalise_date(date, date_period)
      value = Map.get(results_map, key, 0)
      %{date: key, average_duration: value}
    end)
  end

  defp add_duration_date_grouping(query, :hour) do
    from(qa in query,
      group_by: fragment("date_trunc('hour', ?)", qa.inserted_at),
      select: %{
        date: fragment("date_trunc('hour', ?)", qa.inserted_at),
        average_duration: fragment("AVG(EXTRACT(EPOCH FROM (? - ?)) * 1000)", qa.finished_at, qa.inserted_at)
      },
      order_by: [asc: fragment("date_trunc('hour', ?)", qa.inserted_at)]
    )
  end

  defp add_duration_date_grouping(query, :day) do
    from(qa in query,
      group_by: fragment("DATE(?)", qa.inserted_at),
      select: %{
        date: fragment("DATE(?)", qa.inserted_at),
        average_duration: fragment("AVG(EXTRACT(EPOCH FROM (? - ?)) * 1000)", qa.finished_at, qa.inserted_at)
      },
      order_by: [asc: fragment("DATE(?)", qa.inserted_at)]
    )
  end

  defp add_duration_date_grouping(query, :month) do
    from(qa in query,
      group_by: fragment("date_trunc('month', ?)", qa.inserted_at),
      select: %{
        date: fragment("date_trunc('month', ?)", qa.inserted_at),
        average_duration: fragment("AVG(EXTRACT(EPOCH FROM (? - ?)) * 1000)", qa.finished_at, qa.inserted_at)
      },
      order_by: [asc: fragment("date_trunc('month', ?)", qa.inserted_at)]
    )
  end

  defp qa_issues_by_period(project_id, start_datetime, end_datetime, app_name, date_period) do
    query =
      from(qa in Run,
        join: ab in assoc(qa, :app_build),
        join: pr in assoc(ab, :preview),
        join: step in assoc(qa, :run_steps),
        where:
          pr.project_id == ^project_id and
            qa.inserted_at >= ^start_datetime and
            qa.inserted_at < ^end_datetime and
            fragment("array_length(?, 1)", step.issues) > 0
      )

    query =
      query
      |> add_issues_date_grouping(date_period)
      |> apply_app_filter(app_name, [:qa, :ab, :pr, :step])

    results = Repo.all(query)
    results_map = Map.new(results, fn result -> {normalise_date(result.date, date_period), result.count} end)

    date_period
    |> date_range_for_date_period(start_datetime, end_datetime)
    |> Enum.map(fn date ->
      key = normalise_date(date, date_period)
      count = Map.get(results_map, key, 0)
      %{date: key, count: count}
    end)
  end

  defp add_issues_date_grouping(query, :hour) do
    from([qa, ab, pr, step] in query,
      group_by: fragment("date_trunc('hour', ?)", qa.inserted_at),
      select: %{
        date: fragment("date_trunc('hour', ?)", qa.inserted_at),
        count: fragment("SUM(array_length(?, 1))", step.issues)
      },
      order_by: [asc: fragment("date_trunc('hour', ?)", qa.inserted_at)]
    )
  end

  defp add_issues_date_grouping(query, :day) do
    from([qa, ab, pr, step] in query,
      group_by: fragment("DATE(?)", qa.inserted_at),
      select: %{
        date: fragment("DATE(?)", qa.inserted_at),
        count: fragment("SUM(array_length(?, 1))", step.issues)
      },
      order_by: [asc: fragment("DATE(?)", qa.inserted_at)]
    )
  end

  defp add_issues_date_grouping(query, :month) do
    from([qa, ab, pr, step] in query,
      group_by: fragment("date_trunc('month', ?)", qa.inserted_at),
      select: %{
        date: fragment("date_trunc('month', ?)", qa.inserted_at),
        count: fragment("SUM(array_length(?, 1))", step.issues)
      },
      order_by: [asc: fragment("date_trunc('month', ?)", qa.inserted_at)]
    )
  end

  defp apply_app_filter(query, nil, _bindings), do: query
  defp apply_app_filter(query, "any", _bindings), do: query

  defp apply_app_filter(query, app_name, [:qa, :ab, :pr]), do: where(query, [qa, ab, pr], pr.display_name == ^app_name)

  defp apply_app_filter(query, app_name, [:qa, :ab, :pr, :step]),
    do: where(query, [qa, ab, pr, step], pr.display_name == ^app_name)

  @doc """
  Enqueues a TestWorker job for the given QA run.
  """
  def enqueue_test_worker(%Run{} = qa_run) do
    %{"qa_run_id" => qa_run.id}
    |> Tuist.QA.Workers.TestWorker.new()
    |> Oban.insert()
  end

  @doc """
  Prepares logs with metadata (screenshot information) for display and formats them.
  Combines both metadata preparation and formatting into a single pass.
  """
  def prepare_and_format_logs(logs, opts \\ []) do
    hide_usage_logs = Keyword.get(opts, :hide_usage_logs, false)

    logs
    |> filter_usage_logs_if_needed(hide_usage_logs)
    |> Enum.map(&prepare_and_format_log/1)
  end

  @doc """
  Prepares logs with metadata (screenshot information) for display.
  """
  def prepare_logs_with_metadata(logs) do
    Enum.map(logs, &prepare_log_with_metadata/1)
  end

  @doc """
  Prepares a single log with metadata (screenshot information) for display.
  """
  def prepare_log_with_metadata(log) do
    screenshot_metadata = if has_screenshot?(log), do: get_screenshot_metadata(log)
    Map.put(log, :screenshot_metadata, screenshot_metadata)
  end

  @doc """
  Formats logs for display in the logs component.
  Optionally filters out usage logs for public dashboards.
  """
  def format_logs_for_display(logs, opts \\ []) do
    hide_usage_logs = Keyword.get(opts, :hide_usage_logs, false)

    logs
    |> filter_usage_logs_if_needed(hide_usage_logs)
    |> Enum.map(&format_log_for_display/1)
  end

  defp filter_usage_logs_if_needed(logs, true), do: Enum.reject(logs, &(to_atom(&1.type) == :usage))

  defp filter_usage_logs_if_needed(logs, false), do: logs

  defp prepare_and_format_log(log) do
    screenshot_metadata = if has_screenshot?(log), do: get_screenshot_metadata(log)
    log_with_metadata = Map.put(log, :screenshot_metadata, screenshot_metadata)
    format_log_for_display(log_with_metadata)
  end

  defp format_log_for_display(log) do
    type_atom = to_atom(log.type)

    formatted = %{
      type: log_type_display(type_atom),
      message: extract_log_message(log),
      timestamp: format_timestamp(log.timestamp)
    }

    formatted
    |> add_context_if_tool_log(log, type_atom)
    |> add_screenshot_image_if_available(log)
  end

  defp to_atom(type) when is_binary(type), do: String.to_existing_atom(type)
  defp to_atom(type) when is_atom(type), do: type

  defp log_type_display(type) do
    case type do
      :usage -> "TOKENS"
      :tool_call -> "TOOL"
      :tool_call_result -> "RESULT"
      :message -> "ASSISTANT"
    end
  end

  defp extract_log_message(log) do
    case JSON.decode!(log.data) do
      %{"message" => message} -> message
      %{"name" => name} -> name
      %{"input" => input, "output" => output} -> "#{input}/#{output}"
      data -> inspect(data)
    end
  end

  defp format_timestamp(%NaiveDateTime{} = ndt) do
    %{hour: h, minute: m, second: s} = NaiveDateTime.to_time(ndt)
    "#{pad_number(h)}:#{pad_number(m)}:#{pad_number(s)}"
  end

  defp format_timestamp(%DateTime{} = dt) do
    %{hour: h, minute: m, second: s} = DateTime.to_time(dt)
    "#{pad_number(h)}:#{pad_number(m)}:#{pad_number(s)}"
  end

  defp pad_number(n), do: String.pad_leading(to_string(n), 2, "0")

  defp add_context_if_tool_log(formatted, log, type) when type in [:tool_call, :tool_call_result] do
    Map.put(formatted, :context, %{json_data: prettify_json(log.data)})
  end

  defp add_context_if_tool_log(formatted, _log, _type), do: formatted

  defp add_screenshot_image_if_available(formatted, %{screenshot_metadata: %{screenshot_id: screenshot_id}} = log)
       when is_binary(screenshot_id) do
    %{
      account_handle: account_handle,
      project_handle: project_handle,
      qa_run_id: qa_run_id
    } = log.screenshot_metadata

    image_url =
      "/#{account_handle}/#{project_handle}/qa/runs/#{qa_run_id}/screenshots/#{screenshot_id}"

    Map.put(formatted, :image, image_url)
  end

  defp add_screenshot_image_if_available(formatted, _log), do: formatted

  defp prettify_json(data) when is_binary(data) do
    case JSON.decode(data) do
      {:ok, %{"name" => _name, "content" => content} = decoded} when is_list(content) ->
        prettified_content = Enum.map(content, &prettify_content_part/1)
        Jason.encode!(%{decoded | "content" => prettified_content}, pretty: true)

      {:ok, [%{"content" => nested_json, "type" => "text"}]} ->
        case JSON.decode(nested_json) do
          {:ok, parsed_data} ->
            Jason.encode!(parsed_data, pretty: true)

          {:error, _} ->
            nested_json
        end

      {:ok, decoded} ->
        Jason.encode!(decoded, pretty: true)

      {:error, _} ->
        data
    end
  end

  defp prettify_content_part(%{"type" => "text", "content" => content}) when is_binary(content) do
    case JSON.decode(content) do
      {:ok, parsed_json} ->
        %{"type" => "text", "content" => parsed_json}

      {:error, _} ->
        %{"type" => "text", "content" => content}
    end
  end

  defp prettify_content_part(part), do: part

  @action_tools [
    "tap",
    "swipe",
    "long_press",
    "type_text",
    "key_press",
    "button",
    "touch",
    "gesture",
    "plan_report"
  ]

  defp has_screenshot?(log) do
    case JSON.decode(log.data) do
      {:ok, data} ->
        case data do
          %{"name" => "screenshot"} ->
            true

          %{"name" => name, "content" => content} when name in @action_tools ->
            has_screenshot_in_content?(content)

          _ ->
            false
        end

      {:error, _} ->
        false
    end
  end

  defp has_screenshot_in_content?(content) when is_list(content) do
    Enum.any?(content, &has_screenshot_in_text_content?/1)
  end

  defp has_screenshot_in_content?(_), do: false

  defp has_screenshot_in_text_content?(%{"type" => "text", "content" => text_content}) do
    case JSON.decode(text_content) do
      {:ok, nested_data} -> Map.has_key?(nested_data, "screenshot_id")
      {:error, _} -> false
    end
  end

  defp has_screenshot_in_text_content?(_), do: false

  defp get_screenshot_metadata(log) do
    case JSON.decode(log.data) do
      {:ok, data} ->
        case data do
          %{"name" => "screenshot", "content" => content} ->
            find_screenshot_metadata_in_content(content)

          %{"name" => name, "content" => content} when name in @action_tools ->
            find_screenshot_metadata_in_content(content)

          _ ->
            nil
        end

      {:error, _} ->
        nil
    end
  end

  defp find_screenshot_metadata_in_content(content) when is_list(content) do
    Enum.find_value(content, &extract_metadata_from_text_content/1)
  end

  defp find_screenshot_metadata_in_content(_), do: nil

  defp extract_metadata_from_text_content(%{"type" => "text", "content" => text_content}) do
    case JSON.decode(text_content) do
      {:ok,
       %{
         "screenshot_id" => screenshot_id,
         "qa_run_id" => qa_run_id,
         "account_handle" => account_handle,
         "project_handle" => project_handle
       }} ->
        %{
          screenshot_id: screenshot_id,
          qa_run_id: qa_run_id,
          account_handle: account_handle,
          project_handle: project_handle
        }

      _ ->
        nil
    end
  end

  defp extract_metadata_from_text_content(_), do: nil
end
