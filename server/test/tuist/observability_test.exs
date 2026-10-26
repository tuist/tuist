defmodule Tuist.ObservabilityTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Observability
  alias Tuist.Projects.Project
  alias TuistTestSupport.TelemetryCapture

  require Logger

  setup :set_mimic_from_context

  setup do
    stub(Environment, :error_tracking_enabled?, fn -> true end)
    :ok
  end

  test "real Sentry events include searchable IDs, legacy handles and actor-scoped effective decisions" do
    account = %Account{id: 42, name: "tenant", customer_id: "customer"}
    user = %User{id: 7, account: %Account{id: 1, name: "personal"}}
    project = %Project{id: 99, account_id: account.id, name: "app", account: account}
    Observability.set_context(user, %{selected_project: project, ignored: "private input"})
    stub(Environment, :env, fn -> :prod end)
    expect(FunWithFlags, :enabled?, fn :runners, [for: ^account] -> false end)

    refute FeatureFlags.runners_enabled?(account)

    event = Sentry.Event.create_event(exception: %RuntimeError{message: "example"})
    assert event.tags.auth_user_id == 7
    assert event.tags.auth_account_id == 1
    assert event.tags.selected_account_id == 42
    assert event.tags.selected_project_id == 99
    assert event.tags.selected_account_handle == "tenant"
    assert event.tags["feature_flag.runners"] == "false"
    assert event.extra.selected_account_customer_id == "customer"
    assert event.extra.feature_flags == [%{flag: "runners", enabled: false, actor_type: "account", actor_id: 42}]
    refute inspect(event.extra) =~ "private input"
  end

  @tag capture_log: true
  test "task crash reports retain the child's cohort without inheriting the caller's request context" do
    parent = self()

    filter = fn event, owner ->
      if owner in Map.get(event.meta, :callers, []), do: event, else: :stop
    end

    :ok =
      :logger.add_handler(__MODULE__, Sentry.LoggerHandler, %{
        filters: [{:owned_task, {filter, parent}}],
        config: %{metadata: [:file, :line], sync_threshold: nil}
      })

    on_exit(fn -> :logger.remove_handler(__MODULE__) end)

    expect(Sentry, :capture_exception, fn exception, opts ->
      event =
        opts
        |> Keyword.delete(:result)
        |> Keyword.put(:exception, exception)
        |> Sentry.Event.create_event()

      send(parent, {:reported, event})
      {:ok, event.event_id}
    end)

    selected = %Account{id: 42, name: "child"}
    Observability.set_selection(%{selected_account: selected})
    Observability.feature_flag_evaluated(:runners, selected, true)
    snapshot = Observability.snapshot()
    supervisor = start_supervised!(Task.Supervisor)

    {:ok, child} =
      Task.Supervisor.start_child(supervisor, fn ->
        Observability.attach(snapshot)
        send(parent, :attached)

        receive do
          :crash -> raise "task failed"
        end
      end)

    monitor = Process.monitor(child)
    assert_receive :attached, 5_000
    other = %Account{id: 43, name: "parent"}
    Observability.set_selection(%{selected_account: other})
    Observability.feature_flag_evaluated(:runners, other, false)
    Sentry.Context.set_request_context(%{headers: %{"private-header" => "parent-only"}})
    Sentry.Context.set_extra_context(%{private_value: "parent-only"})
    send(child, :crash)

    assert_receive {:reported, event}, 5_000
    assert_receive {:DOWN, ^monitor, :process, ^child, _reason}, 5_000
    assert event.tags.selected_account_id == 42
    assert event.tags["feature_flag.runners"] == "true"
    assert [%{actor_id: 42, enabled: true, flag: "runners"}] = event.extra.feature_flags
    refute Map.has_key?(event.extra, :private_value)
    refute inspect(event.request) =~ "parent-only"
    assert Logger.metadata()[:selected_account_id] == 43
    assert Sentry.Context.get_all().tags["feature_flag.runners"] == "false"
  end

  test "batch evaluations never replace the selected target or attach another tenant's decision" do
    selected = %Account{id: 42, name: "selected"}
    other = %Account{id: 43, name: "other"}
    Observability.set_selection(%{selected_account: selected})
    ref = TelemetryCapture.attach_event_handlers([[:tuist, :feature_flag, :evaluation]])

    assert Observability.feature_flag_evaluated(:runners, selected, true)
    refute Observability.feature_flag_evaluated(:runners, other, false)

    assert_receive {[:tuist, :feature_flag, :evaluation], ^ref, %{count: 1},
                    %{flag: "runners", enabled: true, actor_type: "account", actor_id: 42}}

    assert_receive {[:tuist, :feature_flag, :evaluation], ^ref, %{count: 1},
                    %{flag: "runners", enabled: false, actor_type: "account", actor_id: 43}}

    assert Sentry.Context.get_all().tags["feature_flag.runners"] == "true"
    assert Logger.metadata()[:selected_account_id] == 42
    refute inspect(Sentry.Context.get_all().extra.feature_flags) =~ "43"

    Observability.set_selection(%{selected_account: other})
    refute Map.has_key?(Sentry.Context.get_all().tags, "feature_flag.runners")
    refute Map.has_key?(Sentry.Context.get_all().extra, :feature_flags)
    refute Logger.metadata()[:feature_flags]
  end

  test "a flag actor and an authenticated personal account do not establish a selected tenant" do
    account = %Account{id: 42, name: "personal"}
    Observability.set_authenticated_subject(%User{id: 1, account: account})
    assert Observability.feature_flag_evaluated(:runners, account, true)
    refute Map.has_key?(Sentry.Context.get_all().tags, "feature_flag.runners")
    refute Logger.metadata()[:selected_account_id]

    Observability.clear()
    assert Observability.feature_flag_evaluated(:runners, account, true)
    assert Sentry.Context.get_all().extra == %{}
  end

  test "request reset clears owned keys without deleting other Sentry integrations' context" do
    Sentry.Context.set_request_context(%{url: "https://example.test/scrubbed"})
    Sentry.Context.set_user_context(%{id: "existing-user"})
    Sentry.Context.set_extra_context(%{other_integration: "preserved"})
    Sentry.Context.set_tags_context(%{other_tag: "preserved"})
    Sentry.Context.add_breadcrumb(%{message: "existing breadcrumb"})

    Observability.set_selection(%{selected_account: %Account{id: 42, name: "tenant", customer_id: "customer"}})
    Observability.feature_flag_evaluated(:runners, %Account{id: 42}, true)
    Observability.set_authenticated_subject(nil)

    context = Sentry.Context.get_all()
    assert context.extra == %{other_integration: "preserved"}
    assert context.tags == %{other_tag: "preserved"}
    assert context.request == %{url: "https://example.test/scrubbed"}
    assert context.user == %{id: "existing-user"}
    assert [%{message: "existing breadcrumb"}] = context.breadcrumbs
    refute Logger.metadata()[:selected_account_id]
    refute Logger.metadata()[:selected_account_customer_id]
  end

  test "unknown or removed selections clear stale project and customer IDs" do
    account = %Account{id: 42, name: "tenant", customer_id: "customer"}
    project = %Project{id: 99, account_id: account.id, name: "app", account: account}
    Observability.set_selection(%{selected_project: project})
    Observability.set_selection(%{selected_account: %Account{id: 43, name: "other"}})

    context = Sentry.Context.get_all()
    assert context.tags.selected_account_id == 43
    refute Map.has_key?(context.extra, :selected_account_customer_id)
    refute Map.has_key?(context.extra, :selected_project_id)
    refute Logger.metadata()[:selected_project_id]

    Observability.set_selection(%{})
    assert Sentry.Context.get_all().extra == %{}
    assert Sentry.Context.get_all().tags == %{}
  end

  test "project ownership never pairs a project with another account's handle or cohorts" do
    other = %Account{id: 43, name: "other"}
    project = %Project{id: 99, account_id: 42, name: "app"}
    Observability.set_selection(%{selected_account: other})
    Observability.feature_flag_evaluated(:runners, other, true)
    Observability.set_selection(%{selected_account: other, selected_project: project})

    assert Sentry.Context.get_all().tags.selected_account_id == 42
    assert Sentry.Context.get_all().tags.selected_project_id == 99
    refute Map.has_key?(Sentry.Context.get_all().tags, :selected_account_handle)
    refute Map.has_key?(Sentry.Context.get_all().tags, "feature_flag.runners")
  end

  test "effective evaluations retain short circuits and do not read disabled operands" do
    account = %Account{id: 42, name: "tenant"}
    ref = TelemetryCapture.attach_event_handlers([[:tuist, :feature_flag, :evaluation]])
    stub(Environment, :env, fn -> :can end)
    reject(FunWithFlags, :enabled?, 2)
    assert FeatureFlags.kura_stable_hostname_enabled?(account)

    assert_receive {[:tuist, :feature_flag, :evaluation], ^ref, %{count: 1},
                    %{flag: "kura_stable_hostname", enabled: true, actor_id: 42}}

    stub(Environment, :turnstile_required?, fn -> false end)
    reject(FunWithFlags, :enabled?, 1)
    refute FeatureFlags.turnstile_enabled?()

    assert_receive {[:tuist, :feature_flag, :evaluation], ^ref, %{count: 1},
                    %{flag: "turnstile", enabled: false, actor_type: "global"}}
  end

  test "compound outcomes, rather than raw opt-in gates, are emitted" do
    account = %Account{id: 42}
    stub(Environment, :env, fn -> :prod end)
    ref = TelemetryCapture.attach_event_handlers([[:tuist, :feature_flag, :evaluation]])
    expect(FunWithFlags, :enabled?, fn :immutable_shard_reports, [for: ^account] -> true end)
    expect(FunWithFlags, :enabled?, fn :xcode_coverage, [for: ^account] -> true end)

    refute FeatureFlags.immutable_shard_reports_enabled?(account)

    assert_receive {[:tuist, :feature_flag, :evaluation], ^ref, _, %{flag: "xcode_coverage", enabled: true}}
    assert_receive {[:tuist, :feature_flag, :evaluation], ^ref, _, %{flag: "immutable_shard_reports", enabled: false}}
  end

  test "error context has a fixed decision bound and existing decisions can still change at capacity" do
    flags = ~w(a b c d e f g h i j k l m n o p q r s t u v w x y z aa ab ac ad ae af ag)a
    Enum.each(flags, &Observability.feature_flag_evaluated(&1, nil, true))
    assert length(Sentry.Context.get_all().extra.feature_flags) == 32
    refute Observability.feature_flag_evaluated(:a, nil, false)
    assert Sentry.Context.get_all().tags["feature_flag.a"] == "false"
    assert map_size(Observability.snapshot().context.feature_flags) == 32
  end

  test "Logger output and OTel writes include IDs and decisions, and clear removed attribution" do
    parent = self()
    stub(OpenTelemetry.Tracer, :set_attribute, fn key, value -> send(parent, {:attribute, key, value}) end)
    Observability.set_selection(%{selected_account: %Account{id: 42, name: "tenant"}})
    Observability.feature_flag_evaluated(:runners, %Account{id: 42}, false)

    assert_receive {:attribute, "selected_account_id", 42}
    assert_receive {:attribute, "feature_flag.runners", "false"}

    log =
      capture_log([format: "$metadata$message", metadata: [:selected_account_id, :feature_flags]], fn ->
        Logger.warning("cohort failure")
      end)

    assert log =~ "selected_account_id=42"
    assert log =~ "feature_flag.runners"
    assert log =~ "false"

    Observability.clear()
    assert_receive {:attribute, "selected_account_id", ""}
    assert_receive {:attribute, "feature_flag.runners", ""}
  end

  test "with_context restores caller attribution after exceptions" do
    Observability.set_selection(%{selected_account: %Account{id: 42, name: "caller"}})

    assert_raise RuntimeError, "failure", fn ->
      Observability.with_context(%{selected_account: %Account{id: 43, name: "work"}}, fn ->
        assert Sentry.Context.get_all().tags.selected_account_id == 43
        raise "failure"
      end)
    end

    assert Sentry.Context.get_all().tags.selected_account_id == 42
    assert Logger.metadata()[:selected_account_id] == 42
  end
end
