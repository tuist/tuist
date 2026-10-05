# Seeds a realistic Mix (Elixir) project next to the Xcode data that
# `priv/repo/seeds.exs` creates, so the two dashboards can be compared.
#
#   mix run priv/repo/seeds.exs              # Xcode data (tuist/tuist)
#   mix run priv/repo/seed_mix_analytics.exs # Mix data  (tuist/phoenix-app)
#
# Re-running recreates tuist/phoenix-app with a fresh 60-day history.

import Ecto.Query

alias Tuist.Accounts
alias Tuist.Mix, as: MixAnalytics
alias Tuist.Projects
alias Tuist.Projects.Project
alias Tuist.Repo
alias Tuist.Tests
alias Tuist.Tests.Test.Buffer

:rand.seed(:exsss, {2026, 9, 26})

email = "tuistrocks@tuist.dev"

user =
  case Accounts.get_user_by_email(email) do
    {:ok, user} ->
      user

    {:error, :not_found} ->
      {:ok, user} =
        Accounts.create_user(email,
          password: "tuistrocks",
          confirmed_at: NaiveDateTime.utc_now(),
          setup_billing: false
        )

      user
  end

# Re-stamp the password so the documented credentials work even if the
# password secret rotated since the user was created (same as seeds.exs).
user =
  user
  |> Tuist.Accounts.User.password_changeset(%{password: "tuistrocks", password_confirmation: "tuistrocks"})
  |> Repo.update!()

user_account = Repo.preload(user, :account).account

owner =
  case Accounts.get_organization_by_handle("tuist") do
    nil -> user_account
    organization -> Repo.preload(organization, :account).account
  end

# Recreate the project on every run so the seeded history stays at 60 days
# instead of stacking up. Its old ClickHouse rows are keyed by the old id.
case Repo.get_by(Project, account_id: owner.id, name: "phoenix-app") do
  nil -> :ok
  existing -> {:ok, _} = Projects.delete_project(existing)
end

project = Projects.create_project!(%{name: "phoenix-app", account: %{id: owner.id}}, build_system: :mix)

pick = fn list -> Enum.at(list, :rand.uniform(length(list)) - 1) end
chance = fn probability -> :rand.uniform() < probability end
sha = fn -> 20 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower) end

branches =
  ["main", "main", "main", "feat/live-dashboard", "feat/stripe-webhooks", "fix/n-plus-one-orders", "chore/deps-update"]

toolchains = [{"1.18.4", "27"}, {"1.19.1", "28"}, {"1.19.1", "28"}]

source_files = [
  {"lib/phoenix_app/accounts.ex", "PhoenixApp.Accounts"},
  {"lib/phoenix_app/accounts/user.ex", "PhoenixApp.Accounts.User"},
  {"lib/phoenix_app/billing/stripe_webhook.ex", "PhoenixApp.Billing.StripeWebhook"},
  {"lib/phoenix_app/orders.ex", "PhoenixApp.Orders"},
  {"lib/phoenix_app/orders/order.ex", "PhoenixApp.Orders.Order"},
  {"lib/phoenix_app/workers/send_receipt.ex", "PhoenixApp.Workers.SendReceipt"},
  {"lib/phoenix_app_web/live/dashboard_live.ex", "PhoenixAppWeb.DashboardLive"},
  {"lib/phoenix_app_web/controllers/order_controller.ex", "PhoenixAppWeb.OrderController"},
  {"lib/phoenix_app_web/components/core_components.ex", "PhoenixAppWeb.CoreComponents"}
]

warning_messages = [
  ~s(variable "opts" is unused (if the variable is not meant to be used, prefix it with an underscore\)),
  ~s(variable "changeset" is unused (if the variable is not meant to be used, prefix it with an underscore\)),
  "function build_receipt/2 is unused",
  "module attribute @retry_limit was set but never used",
  "Logger.warn/1 is deprecated. Use Logger.warning/2 instead",
  "the underscored variable \"_socket\" is used after being set",
  "clauses with the same name and arity (number of arguments) must be grouped together, \"def handle_event/3\" was previously defined"
]

error_messages = [
  "undefined function charge_customer/2 (expected PhoenixApp.Billing.StripeWebhook to define such a function or for it to be imported)",
  "undefined variable \"order\"",
  "PhoenixApp.Orders.Order.__struct__/1 is undefined, cannot expand struct PhoenixApp.Orders.Order",
  "cannot compile module PhoenixAppWeb.DashboardLive (errors have been logged)"
]

now = DateTime.utc_now()

diagnostic = fn severity ->
  {file, module} = pick.(source_files)

  %{
    severity: severity,
    file: file,
    module: module,
    message: if(severity == "error", do: pick.(error_messages), else: pick.(warning_messages)),
    line: 10 + :rand.uniform(240),
    column: 3 + :rand.uniform(20),
    compiler: "elixir"
  }
end

# {path, module, typical compile ms, files it waits on}. `phoenix_app_web.ex`
# is the usual Phoenix bottleneck: every controller, LiveView and component
# calls its `use PhoenixAppWeb, ...` macro and has to wait for it.
compile_graph = [
  {"lib/phoenix_app/repo.ex", "PhoenixApp.Repo", 180, []},
  {"lib/phoenix_app/accounts/user.ex", "PhoenixApp.Accounts.User", 420, ["lib/phoenix_app/repo.ex"]},
  {"lib/phoenix_app/accounts.ex", "PhoenixApp.Accounts", 310, ["lib/phoenix_app/accounts/user.ex"]},
  {"lib/phoenix_app/orders/order.ex", "PhoenixApp.Orders.Order", 460, ["lib/phoenix_app/accounts/user.ex"]},
  {"lib/phoenix_app/orders/line_item.ex", "PhoenixApp.Orders.LineItem", 240, ["lib/phoenix_app/orders/order.ex"]},
  {"lib/phoenix_app/orders.ex", "PhoenixApp.Orders", 380,
   ["lib/phoenix_app/orders/order.ex", "lib/phoenix_app/orders/line_item.ex"]},
  {"lib/phoenix_app/billing/stripe_webhook.ex", "PhoenixApp.Billing.StripeWebhook", 290,
   ["lib/phoenix_app/orders/order.ex"]},
  {"lib/phoenix_app/workers/send_receipt.ex", "PhoenixApp.Workers.SendReceipt", 150, ["lib/phoenix_app/orders/order.ex"]},
  {"lib/phoenix_app/mailer.ex", "PhoenixApp.Mailer", 60, []},
  {"lib/phoenix_app_web/gettext.ex", "PhoenixAppWeb.Gettext", 520, []},
  {"lib/phoenix_app_web.ex", "PhoenixAppWeb", 1_450, ["lib/phoenix_app_web/gettext.ex"]},
  {"lib/phoenix_app_web/components/core_components.ex", "PhoenixAppWeb.CoreComponents", 1_900,
   ["lib/phoenix_app_web.ex", "lib/phoenix_app_web/gettext.ex"]},
  {"lib/phoenix_app_web/components/layouts.ex", "PhoenixAppWeb.Layouts", 340,
   ["lib/phoenix_app_web.ex", "lib/phoenix_app_web/components/core_components.ex"]},
  {"lib/phoenix_app_web/router.ex", "PhoenixAppWeb.Router", 780, ["lib/phoenix_app_web.ex"]},
  {"lib/phoenix_app_web/endpoint.ex", "PhoenixAppWeb.Endpoint", 260, ["lib/phoenix_app_web/router.ex"]},
  {"lib/phoenix_app_web/live/dashboard_live.ex", "PhoenixAppWeb.DashboardLive", 640,
   ["lib/phoenix_app_web.ex", "lib/phoenix_app_web/components/core_components.ex"]},
  {"lib/phoenix_app_web/live/order_live/index.ex", "PhoenixAppWeb.OrderLive.Index", 410,
   ["lib/phoenix_app_web.ex", "lib/phoenix_app_web/components/core_components.ex", "lib/phoenix_app/orders/order.ex"]},
  {"lib/phoenix_app_web/live/order_live/show.ex", "PhoenixAppWeb.OrderLive.Show", 350,
   ["lib/phoenix_app_web.ex", "lib/phoenix_app_web/components/core_components.ex"]},
  {"lib/phoenix_app_web/controllers/order_controller.ex", "PhoenixAppWeb.OrderController", 220,
   ["lib/phoenix_app_web.ex"]},
  {"lib/phoenix_app_web/controllers/user_session_controller.ex", "PhoenixAppWeb.UserSessionController", 190,
   ["lib/phoenix_app_web.ex"]},
  {"lib/phoenix_app_web/controllers/page_html.ex", "PhoenixAppWeb.PageHTML", 130,
   ["lib/phoenix_app_web.ex", "lib/phoenix_app_web/components/core_components.ex"]}
]

# Returns {files, steps, elapsed_ms}. Every file starts almost at once, compiles
# until it needs a module another file has not finished defining, and waits
# for it. The list is in dependency order, so a single pass schedules it.
compiled_files = fn clean ->
  compiled =
    if clean do
      compile_graph
    else
      # An incremental compile touches a few files plus whatever depends on them.
      changed = compile_graph |> Enum.take_random(1 + :rand.uniform(2)) |> Enum.map(&elem(&1, 0))
      Enum.filter(compile_graph, fn {path, _, _, deps} -> path in changed or Enum.any?(deps, &(&1 in changed)) end)
    end

  durations = Map.new(compiled, fn {path, _, base, _} -> {path, round(base * 3 * (0.7 + :rand.uniform() * 0.6))} end)
  modules = Map.new(compile_graph, fn {path, module, _, _} -> {path, module} end)

  {files, finished} =
    compiled
    |> Enum.with_index()
    |> Enum.map_reduce(%{}, fn {{path, module, _, deps}, index}, finished ->
      start = 20 + index * 3
      all_deps = deps
      deps = Enum.filter(deps, &Map.has_key?(finished, &1))
      slice = div(durations[path], length(deps) + 1)

      {waits, clock} =
        Enum.flat_map_reduce(deps, start, fn dep, clock ->
          clock = clock + slice

          if finished[dep] > clock do
            wait = %{
              module: modules[dep],
              path: dep,
              kind: if(String.ends_with?(dep, ["user.ex", "order.ex", "line_item.ex"]), do: "struct", else: "module"),
              duration_ms: finished[dep] - clock,
              start_offset_ms: clock
            }

            {[wait], finished[dep]}
          else
            {[], clock}
          end
        end)

      wait_duration = Enum.sum(Enum.map(waits, & &1.duration_ms))

      file = %{
        path: path,
        modules: [module],
        start_offset_ms: start,
        compile_duration_ms: durations[path],
        wait_duration_ms: wait_duration,
        waits: waits,
        # Every file the graph says this one needs, compiled in this run or not.
        dependencies:
          for dep <- all_deps do
            %{
              path: dep,
              kind: if(String.ends_with?(dep, ["user.ex", "order.ex", "line_item.ex"]), do: "export", else: "compile")
            }
          end
      }

      {file, Map.put(finished, path, start + durations[path] + wait_duration)}
    end)

  compiled_at = finished |> Map.values() |> Enum.max(fn -> 0 end)

  # After the files, the compiler writes the modules to disk and type checks
  # each one, then Mix generates the application file.
  write = %{
    category: "write",
    title: "Writing modules to disk",
    start_offset_ms: compiled_at,
    duration_ms: 40 + :rand.uniform(120)
  }

  checks_at = write.start_offset_ms + write.duration_ms

  type_checks =
    for {path, module, _, _} <- compiled do
      %{
        category: "type_check",
        title: "Type checking " <> module,
        path: path,
        start_offset_ms: checks_at + :rand.uniform(60),
        duration_ms: 30 + :rand.uniform(round(durations[path] / 6))
      }
    end

  checked_at = type_checks |> Enum.map(&(&1.start_offset_ms + &1.duration_ms)) |> Enum.max(fn -> checks_at end)

  app = %{
    category: "compiler",
    title: "mix compile.app",
    start_offset_ms: checked_at,
    duration_ms: 15 + :rand.uniform(40)
  }

  {files, [write | type_checks] ++ [app], app.start_offset_ms + app.duration_ms}
end

machine_metrics = fn started_at, duration_ms ->
  samples = max(min(div(duration_ms, 1000), 60), 2)
  start = DateTime.to_unix(started_at, :millisecond) / 1000
  base_memory = 3_200_000_000 + :rand.uniform(800_000_000)

  for i <- 0..(samples - 1) do
    %{
      timestamp: start + i * duration_ms / 1000 / samples,
      cpu_usage_percent: Float.round(55.0 + :rand.uniform() * 40.0, 1),
      memory_used_bytes: base_memory + i * 140_000_000 + :rand.uniform(60_000_000),
      memory_total_bytes: 17_179_869_184,
      # Bytes per second. A compile barely touches the network; it reads
      # sources early and writes the compiled modules throughout.
      network_bytes_in: 2_000 + :rand.uniform(40_000),
      network_bytes_out: 1_000 + :rand.uniform(15_000),
      disk_bytes_read: round(:rand.uniform(6_000_000) * (1 - i / samples) + 200_000),
      disk_bytes_written: 800_000 + :rand.uniform(9_000_000)
    }
  end
end

# ~6 compiles a day over the last 60 days. Clean compiles (CI, dependency
# bumps) also build the dependencies before the project's own files, so they
# take far longer than incremental local compiles. About 7% fail.
mix_builds =
  for day <- 59..0//-1, _ <- 1..(4 + :rand.uniform(4)) do
    started_at = DateTime.add(now, -(day * 86_400 + :rand.uniform(80_000)), :second)
    is_ci = chance.(0.55)
    clean = is_ci and chance.(0.7)
    {files, steps, elapsed_ms} = compiled_files.(clean)
    duration_ms = elapsed_ms + 20 + :rand.uniform(80)
    failed = chance.(0.07)
    {elixir_version, otp_version} = pick.(toolchains)

    warnings = for _ <- 1..:rand.uniform(if(clean, do: 6, else: 3)), chance.(0.6), do: diagnostic.("warning")
    errors = if failed, do: for(_ <- 1..:rand.uniform(2), do: diagnostic.("error")), else: []

    {:ok, build_id} =
      MixAnalytics.create_build(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: user_account.id,
        duration_ms: duration_ms,
        status: if(failed, do: "failure", else: "success"),
        is_ci: is_ci,
        elixir_version: elixir_version,
        otp_version: otp_version,
        mix_env: if(is_ci, do: "test", else: pick.(["dev", "dev", "test"])),
        git_branch: pick.(branches),
        git_commit_sha: sha.(),
        git_ref: "refs/heads/main",
        git_remote_url_origin: "git@github.com:tuist/phoenix-app.git",
        ci_provider: if(is_ci, do: "github"),
        ci_run_id: if(is_ci, do: Integer.to_string(17_000_000_000 + :rand.uniform(999_999))),
        ci_project_handle: if(is_ci, do: "tuist/phoenix-app"),
        ci_host: if(is_ci, do: "https://github.com"),
        contract_version: "0.1",
        custom_tags: if(clean, do: ["clean"], else: []),
        custom_values: if(is_ci, do: %{"workflow" => "ci.yml"}, else: %{}),
        started_at: started_at,
        inserted_at: started_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second),
        diagnostics: warnings ++ errors,
        files: files,
        steps: steps,
        machine_metrics: machine_metrics.(started_at, duration_ms)
      })

    {build_id, clean}
  end

# ExUnit suites. {module, describe, test, flaky?}
suites = [
  {"PhoenixApp.AccountsTest", "register_user/1",
   ["creates a user with valid attrs", "rejects duplicate emails", "hashes the password"], false},
  {"PhoenixApp.AccountsTest", "authenticate/2", ["returns the user for valid credentials", "rejects a wrong password"],
   false},
  {"PhoenixApp.OrdersTest", "create_order/2",
   ["creates an order with line items", "rejects an empty cart", "applies the discount code"], false},
  {"PhoenixApp.OrdersTest", "cancel_order/1", ["refunds a paid order", "cannot cancel a shipped order"], false},
  {"PhoenixApp.Billing.StripeWebhookTest", "handle_event/1",
   ["marks the invoice paid on invoice.paid", "ignores unknown events", "retries on a timeout"], true},
  {"PhoenixApp.Workers.SendReceiptTest", "perform/1", ["delivers the receipt email", "skips cancelled orders"], true},
  {"PhoenixAppWeb.OrderControllerTest", "index", ["lists the orders", "paginates"], false},
  {"PhoenixAppWeb.OrderControllerTest", "create", ["redirects on success", "renders errors when data is invalid"], false},
  {"PhoenixAppWeb.DashboardLiveTest", "mount", ["renders the revenue chart", "updates on new orders"], true},
  {"PhoenixAppWeb.UserSessionControllerTest", nil, ["logs the user in", "logs the user out"], false}
]

test_run_count =
  for day <- 59..0//-1, _ <- 1..(2 + :rand.uniform(3)), reduce: 0 do
    count ->
      ran_at = now |> DateTime.add(-(day * 86_400 + :rand.uniform(80_000)), :second) |> DateTime.to_naive()
      is_ci = chance.(0.7)

      modules =
        suites
        |> Enum.group_by(&elem(&1, 0))
        |> Enum.map(fn {module, describes} ->
          test_cases =
            Enum.flat_map(describes, fn {_, describe, tests, flaky} ->
              Enum.map(tests, fn test_name ->
                failed = if flaky, do: chance.(0.03), else: chance.(0.002)
                duration = if(String.contains?(module, "Web"), do: 30, else: 4) + :rand.uniform(60)

                %{
                  name: test_name,
                  test_suite_name: describe || "",
                  status: if(failed, do: "failure", else: "success"),
                  duration: duration,
                  failures:
                    if failed do
                      [
                        %{
                          message:
                            pick.([
                              "Assertion with == failed\ncode:  assert order.status == :paid\nleft:  :pending\nright: :paid",
                              "** (DBConnection.OwnershipError) cannot find ownership process for #PID<0.512.0>",
                              "** (ExUnit.TimeoutError) test timed out after 60000ms",
                              "expected to receive {:receipt_sent, _}, got nothing after 100ms"
                            ]),
                          path: "test/" <> (module |> Macro.underscore() |> String.replace("_test", "")) <> "_test.exs",
                          line_number: 20 + :rand.uniform(120),
                          issue_type: "assertion_failure"
                        }
                      ]
                    else
                      []
                    end
                }
              end)
            end)

          module_status = if Enum.any?(test_cases, &(&1.status == "failure")), do: "failure", else: "success"

          test_suites =
            test_cases
            |> Enum.reject(&(&1.test_suite_name == ""))
            |> Enum.group_by(& &1.test_suite_name)
            |> Enum.map(fn {name, cases} ->
              %{
                name: name,
                status: if(Enum.any?(cases, &(&1.status == "failure")), do: "failure", else: "success"),
                duration: Enum.sum(Enum.map(cases, & &1.duration))
              }
            end)

          %{
            name: module,
            status: module_status,
            duration: Enum.sum(Enum.map(test_cases, & &1.duration)),
            test_suites: test_suites,
            test_cases: test_cases
          }
        end)

      create_run = fn modules, ran_at, commit, branch ->
        {:ok, _} =
          Tests.create_test(%{
            id: UUIDv7.generate(),
            project_id: project.id,
            account_id: user_account.id,
            build_system: "mix",
            scheme: "",
            git_branch: branch,
            git_commit_sha: commit,
            is_ci: is_ci,
            ci_provider: if(is_ci, do: "github"),
            ran_at: ran_at,
            inserted_at: ran_at,
            status: if(Enum.any?(modules, &(&1.status == "failure")), do: "failure", else: "success"),
            duration: Enum.sum(Enum.map(modules, & &1.duration)) + 1_500 + :rand.uniform(3_000),
            test_modules: modules
          })
      end

      commit = sha.()
      branch = pick.(branches)

      # A failing CI run is the rerun of a commit that had already passed, the
      # way a flaky failure shows up in practice: the server flags a failure
      # as flaky when the same test also passed on the same commit.
      if is_ci and Enum.any?(modules, &(&1.status == "failure")) do
        passing =
          Enum.map(modules, fn module ->
            %{
              module
              | status: "success",
                test_suites: Enum.map(module.test_suites, &%{&1 | status: "success"}),
                test_cases: Enum.map(module.test_cases, &%{&1 | status: "success", failures: []})
            }
          end)

        create_run.(passing, NaiveDateTime.add(ran_at, -900, :second), commit, branch)

        for buffer <- [
              Buffer,
              Tuist.Tests.TestCase.Buffer,
              Tuist.Tests.TestCaseRun.Buffer,
              Tuist.Tests.TestModuleRun.Buffer,
              Tuist.Tests.TestSuiteRun.Buffer
            ],
            do: buffer.flush()
      end

      create_run.(modules, ran_at, commit, branch)

      count + 1
  end

for buffer <- [
      Tuist.Mix.Build.Buffer,
      Tuist.Mix.Diagnostic.Buffer,
      Tuist.Mix.CompiledFile.Buffer,
      Tuist.Mix.Step.Buffer,
      Tuist.Builds.BuildMachineMetric.Buffer,
      Buffer,
      Tuist.Tests.TestCase.Buffer,
      Tuist.Tests.TestCaseRun.Buffer,
      Tuist.Tests.TestModuleRun.Buffer,
      Tuist.Tests.TestSuiteRun.Buffer,
      Tuist.Tests.TestCaseFailure.Buffer
    ] do
  buffer.flush()
end

# A new project's default automation labels a test case flaky once it has
# three flaky runs in 30 days, but it treats what already exists when it
# first runs as the baseline and labels nothing. Seeded history is all
# baseline, so apply the same rule here.
flaky_test_case_ids =
  Tuist.ClickHouseRepo.all(
    from(
      r in subquery(
        from(r in Tuist.Tests.TestCaseRun,
          where: r.project_id == ^project.id and r.ran_at >= ^NaiveDateTime.add(DateTime.to_naive(now), -30, :day),
          group_by: r.id,
          select: %{
            test_case_id: fragment("any(?)", r.test_case_id),
            is_flaky: fragment("argMax(?, ?)", r.is_flaky, r.inserted_at)
          }
        )
      ),
      where: r.is_flaky == true,
      group_by: r.test_case_id,
      having: fragment("count() >= 3"),
      select: r.test_case_id
    )
  )

for test_case_id <- flaky_test_case_ids do
  {:ok, _} = Tests.update_test_case(test_case_id, %{is_flaky: true})
end

IO.puts("Marked #{length(flaky_test_case_ids)} test cases as flaky")

# Everything above lands in one go, so whatever the dashboards date by
# insertion time (the last flaky run, when a test was marked flaky) would all
# read "a minute ago". Date those rows when they would have happened: a flaky
# run when it ran, a test's first run event at its first run, and the flaky
# label at the third flaky run of the window.
seed_params = %{project_id: project.id, since: NaiveDateTime.add(DateTime.to_naive(now), -30, :day), seeded_at: now}

Tuist.IngestRepo.query!(
  "ALTER TABLE flaky_test_case_runs UPDATE inserted_at = ran_at WHERE project_id = {project_id:Int64} SETTINGS mutations_sync = 1",
  seed_params
)

# The events' timestamp is their version column, which ClickHouse cannot
# update, so the labels are written again with the earlier time and the
# originals deleted.
Tuist.IngestRepo.query!(
  """
  INSERT INTO test_case_events (id, test_case_id, project_id, event_type, actor_id, inserted_at, alert_id)
  SELECT e.id, e.test_case_id, e.project_id, e.event_type, e.actor_id, f.marked_at, e.alert_id
  FROM test_case_events AS e
  INNER JOIN (
    SELECT test_case_id, arraySort(groupArray(ran_at))[3] AS marked_at
    FROM flaky_test_case_runs
    WHERE project_id = {project_id:Int64} AND ran_at >= {since:DateTime64(6)}
    GROUP BY test_case_id
    HAVING count() >= 3
  ) AS f ON e.test_case_id = f.test_case_id
  WHERE e.project_id = {project_id:Int64} AND e.event_type = 'marked_flaky'
  """,
  seed_params
)

Tuist.IngestRepo.query!(
  """
  INSERT INTO test_case_events (id, test_case_id, project_id, event_type, actor_id, inserted_at, alert_id)
  SELECT e.id, e.test_case_id, e.project_id, e.event_type, e.actor_id, r.first_ran_at, e.alert_id
  FROM test_case_events AS e
  INNER JOIN (
    SELECT test_case_id, min(ran_at) AS first_ran_at
    FROM test_case_runs
    WHERE project_id = {project_id:Int64}
    GROUP BY test_case_id
  ) AS r ON e.test_case_id = r.test_case_id
  WHERE e.project_id = {project_id:Int64} AND e.event_type = 'first_run'
  """,
  seed_params
)

Tuist.IngestRepo.query!(
  """
  ALTER TABLE test_case_events DELETE
  WHERE project_id = {project_id:Int64} AND event_type IN ('first_run', 'marked_flaky') AND inserted_at >= {seeded_at:DateTime64(6)}
  SETTINGS mutations_sync = 1
  """,
  seed_params
)

xcode_project =
  Repo.one(from(p in Project, join: a in assoc(p, :account), where: a.name == "tuist" and p.name == "tuist"))

base = Tuist.Environment.app_url(route_type: :app)
{latest_mix_build, _} = List.last(mix_builds)
{latest_clean_build, _} = mix_builds |> Enum.filter(&elem(&1, 1)) |> List.last()

IO.puts("""

Seeded #{length(mix_builds)} Mix builds and #{test_run_count} ExUnit runs into #{owner.name}/#{project.name}

  Log in: #{base}/users/log_in  (tuistrocks@tuist.dev / tuistrocks)

  Xcode project overview: #{base}/#{owner.name}/#{(xcode_project && xcode_project.name) || "tuist"}
  Mix project overview:   #{base}/#{owner.name}/#{project.name}
  Mix build runs:         #{base}/#{owner.name}/#{project.name}/builds/build-runs
  Latest Mix build:       #{base}/#{owner.name}/#{project.name}/builds/mix-builds/#{latest_mix_build}
  Latest clean Mix build: #{base}/#{owner.name}/#{project.name}/builds/mix-builds/#{latest_clean_build}
""")
