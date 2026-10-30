defmodule AtlasWeb.AutomationLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.AutomationsFixtures
  import Phoenix.LiveViewTest

  alias Atlas.Automations
  alias Atlas.Automations.Approval
  alias Atlas.Automations.Behavior
  alias Atlas.Automations.Executor
  alias Atlas.Automations.Observability
  alias Atlas.Automations.Revision
  alias Atlas.Automations.Run
  alias Atlas.Automations.Trigger
  alias Atlas.Automations.Workflow
  alias Atlas.Repo

  test "execution details show correlated traces and a paginated event log", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, _} = workflow_fixture(actor)
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    Executor.advance(run.id)
    for _ <- 1..22, do: Observability.record!(run, "worker.started")
    {:ok, view, _} = live(conn, ~p"/automation/executions/#{run.id}")
    assert has_element?(view, "#execution-trace", run.trace_id)
    assert has_element?(view, "#execution-waterfall [data-part='trace-segment']")
    assert has_element?(view, "#execution-event-log.noora-table")
    assert has_element?(view, "#copy-automation-trace[data-clipboard-value='#{run.trace_id}']")
    view |> element("a", "Older events") |> render_click()
    assert_patch(view, ~p"/automation/executions/#{run.id}?events_page=2")
    assert has_element?(view, "#execution-event-log", "Execution admitted and queued.")
    send(view.pid, :refresh)
    assert has_element?(view, "#execution-event-log", "Execution admitted and queued.")
  end

  test "automation is a scoped category with six working destinations", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{scopes: ["automation:write"]})

    for section <- ~w(workflows behaviors executions schedules webhooks approvals) do
      {:ok, view, _} = live(conn, "/automation/#{section}")
      assert has_element?(view, "#sidebar-automation")
      assert has_element?(view, "#sidebar-automation a[href='/automation/#{section}']")
      assert has_element?(view, "#automation-page > [data-part='header'] [data-part='title']")
      assert has_element?(view, "#automation-empty.noora-table")
      assert has_element?(view, "#automation-empty .noora-table-empty-state")
      toolbar = if section == "behaviors", do: "behavior-configurations", else: section
      assert has_element?(view, "##{toolbar}-toolbar")
      assert has_element?(view, "##{toolbar}-search")
      assert has_element?(view, "##{toolbar}-filter-dropdown")
      assert has_element?(view, "##{toolbar}-sort-by")
      refute has_element?(view, "[data-part='panel']")

      if section in ["workflows", "executions"] do
        render_async(view)
        assert has_element?(view, "#automation-analytics")
        assert has_element?(view, "#automation-analytics-empty", "No data yet")
        assert has_element?(view, "#automation-page > [data-part='analytics-filters'] [phx-hook='NooraDatePicker']")
      else
        refute has_element?(view, "#automation-analytics")
      end
    end
  end

  test "unassigned users cannot see the category or navigate to its pages", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, view, _} = live(conn, ~p"/tasks")
    refute has_element?(view, "#sidebar-automation")
    assert {:error, {:redirect, %{to: "/commercial/sales"}}} = live(conn, ~p"/automation/workflows")
  end

  test "creates a ready workflow and starts it without a separate publish step", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {:ok, view, _} = live(conn, ~p"/automation/workflows")
    source = JSON.encode!(%{"steps" => [%{"id" => "value", "behavior" => "core.value", "inputs" => %{}}]})

    view |> element("#open-automation-editor") |> render_click()
    assert has_element?(view, "#automation-editor-modal.noora-modal")
    assert_push_event(view, "open-modal", %{id: "automation-editor-modal"})

    render_hook(view, "save", %{
      "automation" => %{"name" => "Dashboard workflow", "language" => "json", "source" => source}
    })

    {:ok, {[%{id: id}], _}} = Automations.list_workflows(actor)
    assert_push_event(view, "close-modal", %{id: "automation-editor-modal"})
    refute_redirected(view)
    render_hook(view, "editor_open_changed", %{"open" => false})
    assert_redirect(view, ~p"/automation/workflows/#{id}")
    {:ok, detail, _} = live(conn, ~p"/automation/workflows/#{id}")
    assert has_element?(detail, "#run-workflow-modal.noora-modal")
    refute has_element?(detail, "#publish-workflow")
    assert has_element?(detail, "#workflow-detail", "v1")
    refute render(detail) =~ "Draft source"
    refute render(detail) =~ "Published plan"
    assert has_element?(detail, "#workflow-detail.noora-card")
    assert has_element?(detail, "#automation-page [data-part='code-block'][data-language='json'] code span")
    render_hook(detail, "run", %{"run" => %{"input" => "{}"}})
    assert_push_event(detail, "close-modal", %{id: "run-workflow-modal"})
    refute_redirected(detail)
    render_hook(detail, "run_open_changed", %{"open" => false})
    {:ok, {[%{id: run_id}], _}} = Automations.list_runs(actor)
    assert_redirect(detail, ~p"/automation/executions/#{run_id}")
    {:ok, execution, _} = live(conn, ~p"/automation/executions/#{run_id}")
    assert has_element?(execution, "#execution-status", "Queued")
    assert has_element?(execution, "#execution-detail.noora-card")
    assert has_element?(execution, "#execution-attempts.noora-table")
  end

  test "the workflow editor opens beautified JSON without persisting formatting on cancel", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)
    {:ok, view, _} = live(conn, ~p"/automation/workflows/#{workflow.id}")
    html = render_hook(view, "open_editor")
    [textarea] = Regex.run(~r/<textarea[^>]*id="automation_source"[^>]*>.*?<\/textarea>/s, html)
    value = textarea |> LazyHTML.from_fragment() |> LazyHTML.text()
    assert value == Jason.encode!(JSON.decode!(revision.source), pretty: true)
    assert html =~ ~s(phx-hook="CodeEditor")
    render_hook(view, "close_editor")
    assert Repo.get!(Revision, revision.id).source == revision.source
    assert Repo.aggregate(Revision, :count) == 1
  end

  test "the editor preserves malformed drafts and avoids oversized pretty printing", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    large = JSON.encode!(%{"value" => String.duplicate("x", 65_522)})
    assert byte_size(large) < 65_536
    assert byte_size(Jason.encode!(JSON.decode!(large), pretty: true)) > 65_536
    deep = String.duplicate("[", 40) <> "0" <> String.duplicate("]", 40)

    for source <- ["{broken", large, deep] do
      {:ok, workflow} = Automations.create_workflow(actor, %{"name" => "Draft", "source" => source})
      {:ok, view, _} = live(conn, ~p"/automation/workflows/#{workflow.id}")
      html = render_hook(view, "open_editor")
      [textarea] = Regex.run(~r/<textarea[^>]*id="automation_source"[^>]*>.*?<\/textarea>/s, html)
      assert textarea |> LazyHTML.from_fragment() |> LazyHTML.text() == source
    end
  end

  test "published source is the single definition and editing saves a new version", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})

    {workflow, first} =
      workflow_fixture(actor, [
        %{"id" => "value", "behavior" => "core.value", "inputs" => %{"message" => "published-marker"}}
      ])

    {:ok, _} =
      Automations.update_workflow(actor, workflow.id, %{
        "language" => "javascript",
        "source" => "unpublished-marker",
        "input_schema" => %{"type" => "object", "required" => ["unpublished"]}
      })

    {:ok, view, html} = live(conn, ~p"/automation/workflows/#{workflow.id}")
    assert has_element?(view, "#workflow-definition [data-language='json']", "published-marker")
    refute html =~ "unpublished-marker"
    assert html =~ "Save new version"
    view |> element("#open-automation-editor") |> render_click()

    render_hook(view, "change", %{
      "automation" => %{"name" => "Cancelled name", "source" => "cancelled-marker", "language" => "json"}
    })

    send(view.pid, :refresh)
    assert render(view) =~ "cancelled-marker"
    html = render_hook(view, "close_editor")
    refute html =~ "cancelled-marker"
    assert Repo.get!(Workflow, workflow.id).source == "unpublished-marker"
    assert Repo.aggregate(Revision, :count) == 1
    assert Repo.get!(Workflow, workflow.id).published_revision_id == first.id

    source =
      JSON.encode!(%{
        "steps" => [%{"id" => "value", "behavior" => "core.value", "inputs" => %{"message" => "updated-marker"}}]
      })

    render_hook(view, "open_editor")
    render_hook(view, "save", %{"automation" => %{"name" => workflow.name, "source" => source, "language" => "json"}})
    assert_push_event(view, "close-modal", %{id: "automation-editor-modal"})
    render_hook(view, "editor_open_changed", %{"open" => false})
    assert_redirect(view, ~p"/automation/workflows/#{workflow.id}")
    {:ok, updated, _} = live(conn, ~p"/automation/workflows/#{workflow.id}")
    assert has_element?(updated, "#workflow-definition", "updated-marker")
    assert has_element?(updated, "#workflow-detail", "v2")
    assert {:ok, saved} = Automations.get_workflow(actor, workflow.id)
    assert saved.published_revision.input_schema == first.input_schema
    assert Repo.get!(Revision, first.id).source == first.source
  end

  test "invalid edits stay in the modal without changing the published version", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, first} = workflow_fixture(actor)
    {:ok, view, _} = live(conn, ~p"/automation/workflows/#{workflow.id}")
    render_hook(view, "open_editor")
    html = render_hook(view, "save", %{"automation" => %{"name" => "Not saved", "source" => "{"}})
    assert html =~ "Invalid JSON plan."
    send(view.pid, :refresh)
    assert render(view) =~ "Not saved"
    assert Repo.get!(Workflow, workflow.id).name == workflow.name
    assert Repo.get!(Workflow, workflow.id).source == workflow.source
    assert Repo.get!(Workflow, workflow.id).published_revision_id == first.id
    assert Repo.aggregate(Revision, :count) == 1
    render_hook(view, "close_editor")
    assert_push_event(view, "close-modal", %{id: "automation-editor-modal"})
  end

  test "refresh cannot move the edit baseline to a newer version", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, _first} = workflow_fixture(actor)
    {:ok, view, _} = live(conn, ~p"/automation/workflows/#{workflow.id}")
    render_hook(view, "open_editor")
    {:ok, _} = Automations.save_workflow_version(actor, workflow.id, %{"name" => "Newer version"})
    send(view.pid, :refresh)
    render(view)
    html = render_hook(view, "save", %{"automation" => %{"name" => "Stale edit", "source" => workflow.source}})
    assert html =~ "This workflow changed. Reload the page before saving a new version."
    assert Repo.get!(Workflow, workflow.id).name == "Newer version"
    assert Repo.aggregate(Revision, :count) == 2
    render_hook(view, "close_editor")
    send(view.pid, :refresh)
    assert render(view) =~ "Newer version"
    assert has_element?(view, "#workflow-detail", "v2")
  end

  test "invalid new workflows do not create unpublished records", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {:ok, view, _} = live(conn, ~p"/automation/workflows")
    render_hook(view, "open_editor")
    html = render_hook(view, "save", %{"automation" => %{"name" => "Invalid", "source" => "{}"}})
    assert html =~ "A plan requires between 1 and 32 ordered steps."
    assert {:ok, {[], _}} = Automations.list_workflows(actor)
  end

  test "analytics reuse results across metric and pagination patches and refresh on request", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, _} = workflow_fixture(actor)
    {:ok, _} = Automations.run_workflow(actor, workflow.id, %{})

    for index <- 1..20 do
      {:ok, _} = Automations.create_workflow(actor, %{"name" => "Analytics page #{index}", "source" => "{}"})
    end

    {:ok, view, _} = live(conn, ~p"/automation/workflows")
    render_async(view)
    assert has_element?(view, "#automation-metric-executions [data-part='value']", "1")
    assert has_element?(view, "#automation-execution-chart[phx-hook='NooraChart']")
    {:ok, _} = Automations.run_workflow(actor, workflow.id, %{})

    view
    |> element("[phx-click='select_analytics_metric'][phx-value-widget='approvals']")
    |> render_click()

    assert_patch(view, "/automation/workflows?metric=approvals")
    assert has_element?(view, "#automation-execution-chart")
    assert has_element?(view, "#automation-metric-success_rate[data-empty='true'] [data-part='background']")
    refute has_element?(view, "[phx-click='select_analytics_metric'][phx-value-widget='success_rate']")
    assert has_element?(view, "#automation-metric-executions [data-part='value']", "1")
    view |> element("#automation-next") |> render_click()
    assert_patch(view, "/automation/workflows?metric=approvals&page=2")
    assert has_element?(view, "#automation-metric-executions [data-part='value']", "1")
    render_hook(view, "retry_analytics")
    render_async(view)
    assert has_element?(view, "#automation-metric-executions [data-part='value']", "2")
    render_hook(view, "select_analytics_period", %{"days" => "7"})
    assert_patch(view, "/automation/workflows?days=7&metric=approvals&page=1")
    render_async(view)
    assert has_element?(view, "#automation-previous[disabled]")
  end

  test "the server-style date picker persists bounded custom periods and resets to presets", %{conn: conn} do
    {conn, _actor} = log_in_user(conn, %{scopes: ["automation:read"]})
    {:ok, view, _} = live(conn, ~p"/automation/workflows")
    first = Date.to_iso8601(Date.add(Date.utc_today(), -5))
    last = Date.to_iso8601(Date.add(Date.utc_today(), -2))

    render_hook(view, "analytics_period_changed", %{"preset" => "custom", "value" => %{"start" => first, "end" => last}})

    assert_patch(view, "/automation/workflows?days=4&end_date=#{last}&page=1")
    render_async(view)
    assert has_element?(view, "#automation-analytics-period[data-selected-preset='custom']")

    render_hook(view, "analytics_period_changed", %{
      "preset" => "custom",
      "value" => %{"start" => "1900-01-01", "end" => last}
    })

    assert render(view) =~ "Select a date range of 1 to 90 days"
    render_hook(view, "analytics_period_changed", %{"preset" => "last-7-days"})
    assert_patch(view, "/automation/workflows?days=7&page=1")
    render_async(view)
    assert has_element?(view, "#automation-analytics-period[data-selected-preset='last-7-days']")
  end

  test "workflow execution metrics include all its versions but not other workflows", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, _} = workflow_fixture(actor)
    {other, _} = workflow_fixture(actor)
    {:ok, _} = Automations.run_workflow(actor, workflow.id, %{})
    {:ok, _} = Automations.save_workflow_version(actor, workflow.id, %{})
    {:ok, _} = Automations.run_workflow(actor, workflow.id, %{})
    {:ok, _} = Automations.run_workflow(actor, other.id, %{})
    {:ok, view, _} = live(conn, ~p"/automation/workflows/#{workflow.id}")
    render_async(view)
    assert has_element?(view, "#automation-metric-executions [data-part='value']", "2")
    assert has_element?(view, "#workflow-definition")
    render_hook(view, "select_analytics_metric", %{"widget" => "invalid"})
    assert has_element?(view, "#automation-execution-chart")
  end

  test "the execution table and metrics share the selected admission period", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)
    {:ok, recent} = Automations.run_workflow(actor, workflow.id, %{})
    started_at = DateTime.add(DateTime.utc_now(), -60 * 86_400) |> DateTime.truncate(:second)

    old =
      Atlas.Repo.insert!(%Run{
        revision_id: revision.id,
        initiated_by_id: actor.id,
        status: "succeeded",
        trigger: "manual",
        inserted_at: started_at,
        updated_at: started_at,
        completed_at: DateTime.add(started_at, 10)
      })

    {:ok, view, _} = live(conn, ~p"/automation/executions?days=7")
    render_async(view)
    assert has_element?(view, "#automation-metric-executions [data-part='value']", "1")
    assert has_element?(view, "a[href='/automation/executions/#{recent.id}']")
    refute has_element?(view, "a[href='/automation/executions/#{old.id}']")
    render_hook(view, "select_analytics_period", %{"days" => "90"})
    render_async(view)
    assert has_element?(view, "#automation-metric-executions [data-part='value']", "2")
    assert has_element?(view, "a[href='/automation/executions/#{old.id}']")
    assert has_element?(view, "#automation-metric-duration [data-part='value']", "10s")
  end

  test "JavaScript drafts are highlighted without executing them", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})

    {:ok, workflow} =
      Automations.create_workflow(actor, %{
        "name" => "JavaScript draft",
        "language" => "javascript",
        "source" => ~S|return {steps: []}; // <script>unsafe</script>|
      })

    {:ok, view, _} = live(conn, ~p"/automation/workflows/#{workflow.id}")
    assert has_element?(view, "#automation-page [data-language='javascript'] code.language-javascript span")
    refute has_element?(view, "#automation-page script")
    send(view.pid, :refresh)
    assert render(view) =~ "language-javascript"
  end

  test "domain catalog is searchable, versioned and exposes inspectable contracts", %{conn: conn} do
    {conn, _} = log_in_user(conn, %{scopes: ["automation:read"]})
    {:ok, view, _} = live(conn, ~p"/automation/behaviors")
    assert has_element?(view, "#behavior-types-table", "accounts.create@1")
    assert has_element?(view, "#behavior-types-table", "notes.delete@1")
    render_change(element(view, "#behavior-types-search-form"), %{"table_search" => %{"query" => "notes.delete"}})
    assert has_element?(view, "#behavior-types-table", "notes.delete@1")
    refute has_element?(view, "#behavior-types-table", "accounts.create@1")
    html = render_hook(view, "inspect_type", %{"reference" => "notes.delete@1"})
    assert html =~ "requires_approval"
    assert html =~ "target_step"
    assert html =~ "notes:write"
    assert_push_event(view, "open-modal", %{id: "behavior-contract-modal"})
    render_hook(view, "type_contract_open_changed", %{"open" => false})
    refute has_element?(view, "#behavior-contract")
  end

  test "behavior controls use one section and retain filter/search/sort state in the URL", %{conn: conn} do
    {conn, _} = log_in_user(conn, %{scopes: ["automation:read"]})
    path = "/automation/behaviors?q=notes&filter_domain_op=%3D%3D&filter_domain_val=notes&sort_by=name&sort_order=desc"
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#behavior-types [data-part='records-section'] #behavior-types-toolbar")
    assert has_element?(view, "#behavior-types [data-part='records-section'] #behavior-types-table")
    assert has_element?(view, "#behavior-types-active-filters", "Domain")
    assert has_element?(view, "#behavior-types-sort-by", "Sort by:")
    refute has_element?(view, "#behavior-types-table", "accounts.create@1")
    assert has_element?(view, "#behavior-types-table tbody tr:first-child", "notes.update@1")
    view |> element("#behavior-types-table thead a", "Type") |> render_click()

    assert_patch(
      view,
      ~p"/automation/behaviors?#{%{"q" => "notes", "filter_domain_op" => "==", "filter_domain_val" => "notes", "sort_by" => "name", "sort_order" => "asc"}}"
    )

    render_hook(view, "update_filter", %{"type" => "delete", "payload_filter_id" => "domain"})
    refute has_element?(view, "#behavior-types-active-filters")
    send(view.pid, :refresh)
    assert has_element?(view, "#behavior-types-search[value='notes']")
    assert has_element?(view, "#behavior-types-table", "notes.create@1")
  end

  test "execution controls filter before pagination and survive refresh, sorting and period changes", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)

    for _ <- 1..23 do
      Repo.insert!(%Run{
        revision_id: revision.id,
        initiated_by_id: actor.id,
        status: "failed",
        trigger: "manual",
        input: %{},
        outputs: %{}
      })
    end

    Repo.insert!(%Run{
      revision_id: revision.id,
      initiated_by_id: actor.id,
      status: "succeeded",
      trigger: "webhook",
      input: %{},
      outputs: %{}
    })

    {:ok, view, _} = live(conn, "/automation/executions?filter_status_op=%3D%3D&filter_status_val=failed&days=7")
    render_async(view)
    assert has_element?(view, "#executions-toolbar")
    assert has_element?(view, "#executions-active-filters", "Failed")
    assert has_element?(view, "#automation-items", workflow.name)
    refute has_element?(view, "#automation-items", "Succeeded")
    view |> element("#automation-next") |> render_click()
    assert has_element?(view, "#automation-items tbody tr:nth-child(3)")
    refute has_element?(view, "#automation-items tbody tr:nth-child(4)")
    send(view.pid, :refresh)
    assert has_element?(view, "#executions-active-filters", "Failed")
    assert has_element?(view, "#automation-items tbody tr:nth-child(3)")
    refute has_element?(view, "#automation-items tbody tr:nth-child(4)")
    view |> element("#automation-items thead a", "Created") |> render_click()
    assert has_element?(view, "#automation-items tbody tr:nth-child(20)")
    refute has_element?(view, "#automation-items tbody tr:nth-child(21)")
    render_change(element(view, "#executions-search-form"), %{"table_search" => %{"query" => "no-such-workflow"}})
    assert has_element?(view, "#automation-empty", "No matching executions")
    assert has_element?(view, "#executions-toolbar")
    assert has_element?(view, "#executions-active-filters", "Failed")
    render_hook(view, "select_analytics_period", %{"days" => "30"})
    assert has_element?(view, "#executions-search[value='no-such-workflow']")
    assert has_element?(view, "#executions-active-filters", "Failed")
  end

  test "invalid table options and forged filters are harmless", %{conn: conn} do
    {conn, _} = log_in_user(conn, %{scopes: ["automation:read"]})

    {:ok, view, _} =
      live(
        conn,
        "/automation/behaviors?sort_by=source&sort_order=sideways&filter_domain_op=%3D%3D&filter_domain_val=unknown&q[bad]=x"
      )

    assert has_element?(view, "#behavior-types-table", "notes.create@1")
    render_hook(view, "add_filter", %{"value" => "unknown"})
    render_hook(view, "update_filter", %{"payload_filter_id" => "domain", "type" => "change_value", "value" => %{}})
    assert has_element?(view, "#behavior-types-table", "notes.create@1")
  end

  test "behavior configuration uses a modal and the shared table", %{conn: conn} do
    {conn, _actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {:ok, view, _} = live(conn, ~p"/automation/behaviors")
    assert has_element?(view, "#behavior-types-table.noora-table", "javascript.evaluate")

    render_hook(view, "save", %{
      "automation" => %{"name" => "Reusable context", "type" => "core.value", "configuration" => "{}"}
    })

    assert has_element?(view, "#automation-items tbody tr", "Reusable context")
    refute has_element?(view, "#automation-empty")
    assert_push_event(view, "close-modal", %{id: "automation-editor-modal"})
    send(view.pid, :refresh)
    assert render(view) =~ "Reusable context"
  end

  test "schedule and webhook controls compose, persist and stay available for empty results", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)

    for {section, kind} <- [{"schedules", "schedule"}, {"webhooks", "webhook"}] do
      for {name, enabled} <- [{"Nightly Alpha", true}, {"Nightly Beta", false}] do
        Repo.insert!(%Trigger{
          name: name,
          kind: kind,
          enabled: enabled,
          revision_id: revision.id,
          execution_user_id: actor.id,
          cron: "0 9 * * 1"
        })
      end

      {:ok, view, _} = live(conn, "/automation/#{section}?page=3")
      render_change(element(view, "##{section}-search-form"), %{"table_search" => %{"query" => "Nightly"}})
      assert has_element?(view, "#automation-items", "Nightly Alpha")
      assert has_element?(view, "#automation-items", "Nightly Beta")
      render_hook(view, "add_filter", %{"value" => "status"})

      render_hook(view, "update_filter", %{
        "payload_filter_id" => "status",
        "type" => "change_value",
        "value" => "enabled"
      })

      assert has_element?(view, "##{section}-active-filters", "Enabled")
      assert has_element?(view, "#automation-items", "Nightly Alpha")
      refute has_element?(view, "#automation-items", "Nightly Beta")
      render_hook(view, "add_filter", %{"value" => "workflow"})

      render_hook(view, "update_filter", %{
        "payload_filter_id" => "workflow",
        "type" => "change_value",
        "value" => workflow.name
      })

      assert has_element?(view, "##{section}-active-filters", workflow.name)
      view |> element("#automation-items thead a", "Name") |> render_click()
      send(view.pid, :refresh)
      assert has_element?(view, "#automation-items", "Nightly Alpha")
      refute has_element?(view, "#automation-items", "Nightly Beta")
      render_hook(view, "update_filter", %{"payload_filter_id" => "status", "type" => "delete"})
      assert has_element?(view, "#automation-items", "Nightly Beta")
      render_change(element(view, "##{section}-search-form"), %{"table_search" => %{"query" => "missing-trigger"}})
      assert has_element?(view, "#automation-empty", "No matching records")
      assert has_element?(view, "##{section}-toolbar")
    end
  end

  test "approval filters include cancelled records and preserve exact review actions", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)
    run = Repo.insert!(%Run{revision_id: revision.id, initiated_by_id: actor.id})

    for status <- ~w(pending cancelled approved) do
      Repo.insert!(%Approval{
        run_id: run.id,
        reviewer_id: actor.id,
        step_id: "review_#{status}",
        status: status,
        payload: %{"private" => "private-approval-payload"}
      })
    end

    {:ok, view, _} = live(conn, "/automation/approvals?filter_status_op=%3D%3D&filter_status_val=cancelled")
    assert has_element?(view, "#approvals-active-filters", "Cancelled")
    assert has_element?(view, "#automation-items", "review_cancelled")
    refute has_element?(view, "#automation-items", "review_pending")
    assert has_element?(view, "#automation-items button", "Review")
    render_change(element(view, "#approvals-search-form"), %{"table_search" => %{"query" => workflow.name}})
    view |> element("#automation-items thead a", "Reviewer") |> render_click()
    send(view.pid, :refresh)
    assert has_element?(view, "#automation-items", "review_cancelled")

    render_change(element(view, "#approvals-search-form"), %{"table_search" => %{"query" => "private-approval-payload"}})

    assert has_element?(view, "#automation-empty", "No matching records")
    assert has_element?(view, "#approvals-toolbar")
  end

  test "saved configuration controls are independent of behavior catalog controls", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})

    for name <- ["Alpha context", "Beta context"] do
      Repo.insert!(%Behavior{name: name, type: "core.value", created_by_id: actor.id})
    end

    {:ok, view, _} =
      live(conn, "/automation/behaviors?q=notes.delete&config_q=Alpha&config_sort_by=name&config_sort_order=asc")

    assert has_element?(view, "#automation-items", "Alpha context")
    refute has_element?(view, "#automation-items", "Beta context")
    assert has_element?(view, "#behavior-types-table", "notes.delete@1")
    refute has_element?(view, "#behavior-types-table", "tasks.create")

    render_change(element(view, "#behavior-configurations-search-form"), %{
      "table_prefix" => "config_",
      "table_search" => %{"query" => "Beta"}
    })

    assert has_element?(view, "#automation-items", "Beta context")
    refute has_element?(view, "#automation-items", "Alpha context")
    assert has_element?(view, "#behavior-types-search[value='notes.delete']")
    render_hook(view, "add_filter", %{"value" => "config_behavior_type"})

    render_hook(view, "update_filter", %{
      "payload_filter_id" => "config_behavior_type",
      "type" => "change_value",
      "value" => "core.value"
    })

    assert has_element?(view, "#behavior-configurations-active-filters", "core.value")
    assert has_element?(view, "#automation-items", "Beta context")
    view |> element("#automation-items thead a", "Name") |> render_click()
    assert has_element?(view, "#behavior-types-search[value='notes.delete']")
    send(view.pid, :refresh)
    assert has_element?(view, "#automation-items", "Beta context")
    assert has_element?(view, "#behavior-types-table", "notes.delete@1")
  end

  test "workflow controls filter publication and effective language", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, _} = workflow_fixture(actor)

    {:ok, _} =
      Automations.create_workflow(actor, %{
        "name" => "Unpublished JS",
        "language" => "javascript",
        "source" => "return {steps: []};"
      })

    {:ok, view, _} =
      live(
        conn,
        "/automation/workflows?filter_status_op=%3D%3D&filter_status_val=published&filter_language_op=%3D%3D&filter_language_val=json"
      )

    render_async(view)
    assert has_element?(view, "#workflows-active-filters", "Published")
    assert has_element?(view, "#automation-items", workflow.name)
    refute has_element?(view, "#automation-items", "Unpublished JS")
    view |> element("#automation-items thead a", "Language") |> render_click()
    send(view.pid, :refresh)
    assert has_element?(view, "#automation-items", workflow.name)
  end

  test "trigger tables show workflow context and update without leaving the page", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, _revision} = workflow_fixture(actor)

    for section <- ~w(schedules webhooks) do
      {:ok, view, _} = live(conn, "/automation/#{section}")

      render_hook(view, "save", %{
        "automation" => %{
          "name" => "Dashboard trigger",
          "workflow_id" => workflow.id,
          "cron" => "0 9 * * 1",
          "input" => "{}"
        }
      })

      assert has_element?(view, "#automation-items tbody tr", workflow.name)
      assert has_element?(view, "#automation-items .noora-badge", "Enabled")
      assert_push_event(view, "close-modal", %{id: "automation-editor-modal"})
      if section == "webhooks", do: assert(has_element?(view, "#webhook-credential.noora-card"))
      view |> element("#automation-items button[phx-click='toggle']") |> render_click()
      assert has_element?(view, "#automation-items .noora-badge", "Paused")
    end
  end

  test "pagination uses the shared buttons and disables page boundaries", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})

    for index <- 1..21 do
      {:ok, _} = Automations.create_workflow(actor, %{"name" => "Workflow #{index}", "source" => "{}"})
    end

    {:ok, view, _} = live(conn, ~p"/automation/workflows")
    assert has_element?(view, "#automation-previous.noora-button[disabled]")
    view |> element("#automation-next") |> render_click()
    assert_patch(view, ~p"/automation/workflows?page=2")
    assert has_element?(view, "#automation-next.noora-button[disabled]")
    assert has_element?(view, "#automation-previous[href='/automation/workflows?page=1']")
  end

  test "readers cannot invoke write events even with crafted messages", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:read"]})
    {:ok, view, _} = live(conn, ~p"/automation/workflows")
    refute has_element?(view, "#open-automation-editor")
    render_hook(view, "save", %{"automation" => %{"name" => "Denied", "source" => "{}"}})
    assert {:ok, {[], _}} = Automations.list_workflows(actor)
    assert has_element?(view, "#flash-error")
  end

  test "approval inbox renders the exact payload and records a review", %{conn: conn} do
    {conn, actor} = log_in_user(conn, %{scopes: ["automation:write"]})

    {workflow, _} =
      workflow_fixture(actor, [
        %{
          "id" => "review",
          "type" => "approval",
          "reviewer_id" => actor.id,
          "inputs" => %{"message" => "Review exactly this"}
        }
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    Executor.advance(run.id)
    approval = Repo.get_by!(Approval, run_id: run.id)
    {:ok, view, _} = live(conn, ~p"/automation/approvals")
    assert has_element?(view, "#automation-items.noora-table #items-#{approval.id}", "review")
    refute has_element?(view, "#approve-#{approval.id}")
    html = view |> element("#review-#{approval.id}") |> render_click()
    assert html =~ "Review exactly this"
    assert html =~ ~s(data-part="code-block")
    assert html =~ "color: light-dark("
    assert_push_event(view, "open-modal", %{id: "approval-review-modal"})
    render_hook(view, "decide", %{"id" => approval.id, "decision" => "approved"})
    assert_push_event(view, "close-modal", %{id: "approval-review-modal"})
    assert Repo.get!(Approval, approval.id).payload == %{"message" => "Review exactly this"}
    assert Repo.get!(Approval, approval.id).status == "approved"
  end
end
