defmodule Tuist.EntireTrailsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Tuist.Entire.Client, as: Entire
  alias Tuist.Entire.Installation
  alias Tuist.Entire.Workers.DeliveryWorker
  alias Tuist.EntireTrails
  alias Tuist.EntireTrails.Summary
  alias Tuist.EntireTrails.Workers.ReportWorker
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.VCS
  alias Tuist.VCS.Workers.CommentWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  @sha String.duplicate("a", 40)
  @other_sha String.duplicate("b", 40)
  @api "https://aws-eu-central-1.api.entire.io"

  setup do
    project = ProjectsFixtures.project_fixture()
    account = Repo.preload(project, :account).account
    installation = Repo.insert!(%Installation{account_id: account.id, remote_id: "ins_#{account.id}"})
    {_, pem} = JOSE.JWK.to_pem(JOSE.JWK.generate_key({:okp, :Ed25519}))

    stub(Entire, :config, fn ->
      [slug: "tuist", private_key: pem, delivery_jwks_url: "https://delivery.entire.io/.well-known/jwks.json"]
    end)

    stub(KeyValueStore, :get, fn _ -> nil end)
    stub(KeyValueStore, :put, fn _, _, _ -> :ok end)
    stub(FunWithFlags, :enabled?, fn flag, _ -> flag == :entire_trails end)

    {:ok, remote} =
      Agent.start_link(fn ->
        %{
          head: @sha,
          status: "open",
          summaries: %{},
          checks: %{},
          reviews: %{},
          writes: 0,
          fail_after_create: false,
          revoked: false,
          # Someone quoting Tuist's marker must not have their comment edited.
          discussions: %{
            "human" => %{
              "identity" => %{"kind" => "user", "username" => "octocat"},
              "messages" => [%{"id" => "human-message", "body" => "<!-- tuist-project:#{project.id} -->"}]
            }
          },
          lose_comment: false,
          deny_discussions: false
        }
      end)

    stub(Req, :request, fn opts -> request(opts, remote, installation) end)

    attrs = %{project_id: project.id, installation_id: installation.id, repository_id: "repo_selected"}
    {:ok, connection} = EntireTrails.connect(account, attrs)

    %{
      project: project,
      account: account,
      installation: installation,
      attrs: attrs,
      connection: connection,
      remote: remote
    }
  end

  test "publishes current-commit checks and head-pinned reviews without duplicate retries", context do
    build(context.project, @sha, "Current", 1)
    build(context.project, @other_sha, "Stale", 2)

    assert :ok = EntireTrails.sync(context.connection.id)
    [summary] = Agent.get(context.remote, &Map.values(&1.summaries))
    [%{"id" => comment_id} = comment] = comments(context)
    assert comment["title"] == "Tuist insights for #{context.account.name}/#{context.project.name}"
    assert comment["body"] == summary["body"] <> "\n\n<!-- tuist-project:#{context.project.id} -->"
    assert summary["body"] =~ "Current"
    refute summary["body"] =~ "Stale"
    assert summary["body"] =~ "`aaaaaaaaa`"
    refute summary["body"] =~ "/commit/"
    assert summary["body"] =~ "/#{context.account.name}/#{context.project.name}/builds/build-runs/"
    handle = "#{context.account.name}/#{context.project.name}"
    [%{check_suite: suite, check_runs: [run]}] = Agent.get(context.remote, &Map.values(&1.checks))
    assert suite.key == handle
    assert suite.details_url == Environment.app_url(path: "/" <> handle)
    assert run.details_url == suite.details_url

    build(context.project, @sha, "Later", 3)
    assert :ok = EntireTrails.sync(context.connection.id)
    summaries = Agent.get(context.remote, &Map.values(&1.summaries))
    assert length(summaries) == 2
    body = Enum.find_value(summaries, fn summary -> if summary["body"] =~ "Later", do: summary["body"] end)
    assert body =~ "Current"
    assert body =~ "Later"
    assert [%{"id" => ^comment_id, "body" => comment_body}] = comments(context)
    assert comment_body =~ "Later"

    assert :ok = EntireTrails.sync(context.connection.id)
    assert map_size(Agent.get(context.remote, & &1.summaries)) == 2
    assert map_size(Agent.get(context.remote, & &1.checks)) == 2
    assert Repo.aggregate(Summary, :count) == 1

    assert {:ok, _} = EntireTrails.disconnect(context.account, context.connection.id)
    assert Repo.aggregate(Summary, :count) == 0
    assert :ok = EntireTrails.sync(context.connection.id)
    assert map_size(Agent.get(context.remote, & &1.summaries)) == 2
  end

  test "recovers a successful create whose response was lost without posting a duplicate", context do
    build(context.project, @sha, "App", 1)
    Agent.update(context.remote, &%{&1 | fail_after_create: true})

    assert {:error, :unavailable} = EntireTrails.sync(context.connection.id)
    assert Repo.aggregate(Summary, :count) == 1
    build(context.project, @sha, "Arrived during retry", 2)
    assert :ok = EntireTrails.sync(context.connection.id)
    assert map_size(Agent.get(context.remote, & &1.summaries)) == 1
    assert map_size(Agent.get(context.remote, & &1.reviews)) == 1
    assert map_size(Agent.get(context.remote, & &1.checks)) == 1
    assert Repo.aggregate(Summary, :count) == 1
    assert :ok = EntireTrails.sync(context.connection.id)
    assert map_size(Agent.get(context.remote, & &1.summaries)) == 2
  end

  test "keeps one Trail comment after a lost create response or a deleted comment", context do
    build(context.project, @sha, "App", 1)
    Agent.update(context.remote, &%{&1 | lose_comment: true})

    assert {:error, :unavailable} = EntireTrails.sync(context.connection.id)
    build(context.project, @sha, "Arrived during retry", 2)
    # The retry recovers the started attempt; the follow-up edits the same comment.
    assert :ok = EntireTrails.sync(context.connection.id)
    assert [%{"id" => id}] = comments(context)
    assert %{discussion_id: ^id, message_id: "message-" <> ^id} = Repo.one!(Summary)
    assert :ok = EntireTrails.sync(context.connection.id)
    assert [%{"id" => ^id, "body" => body}] = comments(context)
    assert body =~ "Arrived during retry"

    Agent.update(context.remote, &%{&1 | discussions: Map.delete(&1.discussions, id)})
    build(context.project, @sha, "After deletion", 3)
    assert :ok = EntireTrails.sync(context.connection.id)
    assert [%{"id" => new_id, "body" => body}] = comments(context)
    assert new_id != id
    assert body =~ "After deletion"

    human = Agent.get(context.remote, & &1.discussions["human"])
    assert human["messages"] == [%{"id" => "human-message", "body" => "<!-- tuist-project:#{context.project.id} -->"}]
  end

  test "publishes checks and findings for installations that have not granted discussions", context do
    build(context.project, @sha, "App", 1)
    Agent.update(context.remote, &%{&1 | deny_discussions: true})

    assert :ok = EntireTrails.sync(context.connection.id)
    assert comments(context) == []
    assert map_size(Agent.get(context.remote, & &1.checks)) == 1
    assert map_size(Agent.get(context.remote, & &1.summaries)) == 1
    summary = Repo.one!(Summary)
    assert summary.published_at == summary.reported_at
    assert summary.discussion_id == nil
  end

  for insights_available? <- [false, true] do
    @tag insights_available?: insights_available?
    test "recovers findings after a lost response and head advance (new insights: #{insights_available?})", context do
      stub(VCS, :get_run_report_sections, fn %{git_commit_sha: sha} ->
        cond do
          sha == @sha -> %{summary: "Head A failed", failed_tests: "LoginTests failed", flaky_tests: nil}
          context.insights_available? -> %{summary: "Head B passed", failed_tests: nil, flaky_tests: nil}
          true -> nil
        end
      end)

      Agent.update(context.remote, &%{&1 | fail_after_create: true})
      assert {:error, :unavailable} = EntireTrails.sync(context.connection.id)
      initial = Agent.get(context.remote, & &1)
      Agent.update(context.remote, &%{&1 | head: @other_sha})

      # Recover A whether or not B has insights, without creating another review.
      assert :ok = EntireTrails.sync(context.connection.id)
      recovered = Agent.get(context.remote, & &1)
      assert recovered.summaries == initial.summaries
      assert recovered.reviews == initial.reviews
      assert recovered.checks == initial.checks
      [summary] = Repo.all(Summary)
      assert summary.head_sha == @sha
      assert [finding_id] = summary.finding_ids
      assert summary.published_at == summary.reported_at

      stub(VCS, :get_run_report_sections, fn %{git_commit_sha: sha} ->
        assert sha == @other_sha
        %{summary: "Head B passed", failed_tests: nil, flaky_tests: nil}
      end)

      assert :ok = EntireTrails.sync(context.connection.id)
      final = Agent.get(context.remote, & &1)
      assert map_size(final.reviews) == 2
      assert Map.has_key?(final.resolved, summary.review_id <> "/comments/" <> finding_id)
      [current] = Repo.all(Summary)
      assert current.head_sha == @other_sha
      assert current.finding_ids == []
      assert current.report_body == "Head B passed"
    end
  end

  test "check publications leave the legacy discussion publisher's table unchanged", context do
    build(context.project, @sha, "App", 1)
    assert :ok = EntireTrails.sync(context.connection.id)
    legacy_query = from(s in "entire_trail_summaries", select: map(s, [:discussion_id, :message_id]))
    assert Repo.all(legacy_query) == []

    # An old replica can still create a valid pointer after a Checks publication.
    legacy = %{
      id: Ecto.UUID.dump!(Ecto.UUID.generate()),
      connection_id: Ecto.UUID.dump!(context.connection.id),
      trail_id: "trail_stable",
      discussion_id: "legacy-discussion",
      message_id: "legacy-message",
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    Repo.insert_all("entire_trail_summaries", [legacy])
    build(context.project, @sha, "Later", 2)
    assert :ok = EntireTrails.sync(context.connection.id)
    assert Repo.all(legacy_query) == [%{discussion_id: "legacy-discussion", message_id: "legacy-message"}]
    assert Repo.aggregate(Summary, :count) == 1

    assert {:ok, _} = EntireTrails.disconnect(context.account, context.connection.id)
    assert Repo.all(legacy_query) == []
    assert Repo.aggregate(Summary, :count) == 0
  end

  test "does not publish absent, closed, or changed-head results", context do
    assert :ok = EntireTrails.sync(context.connection.id)
    build(context.project, @sha, "App", 1)

    for status <- ["closed", "merged"] do
      Agent.update(context.remote, &%{&1 | status: status})
      assert :ok = EntireTrails.sync(context.connection.id)
    end

    Agent.update(context.remote, &%{&1 | status: "open", head: nil})
    assert :ok = EntireTrails.sync(context.connection.id)
    Agent.update(context.remote, &%{&1 | head: @sha})

    stub(VCS, :get_run_report_sections, fn _ ->
      Agent.update(context.remote, &%{&1 | head: @other_sha})
      %{summary: "Old results", failed_tests: nil, flaky_tests: nil}
    end)

    assert :ok = EntireTrails.sync(context.connection.id)
    assert Agent.get(context.remote, & &1.writes) == 0

    # A never-started old snapshot must not be published as part of recovery.
    stub(VCS, :get_run_report_sections, fn %{git_commit_sha: sha} ->
      assert sha == @other_sha
      %{summary: "New results", failed_tests: nil, flaky_tests: nil}
    end)

    assert :ok = EntireTrails.sync(context.connection.id)
    [report] = Agent.get(context.remote, &Map.values(&1.summaries))
    assert report["body"] == "New results"
    assert map_size(Agent.get(context.remote, & &1.reviews)) == 1
  end

  test "distinguishes an empty Trail list from a missing items field", context do
    for body <- [%{"items" => []}, %{"trails" => [%{"number" => 7}]}] do
      stub(Req, :request, fn opts ->
        if opts[:url] == @api <> "/api/v1/repos/repo_selected/trails" do
          response(200, body)
        else
          request(opts, context.remote, context.installation)
        end
      end)

      log = capture_log(fn -> assert :ok = EntireTrails.sync(context.connection.id) end)
      assert log =~ "response missing items" == not Map.has_key?(body, "items")
      assert Agent.get(context.remote, & &1.writes) == 0
    end
  end

  test "links to Tuist when the report exceeds Entire's UTF-8 byte limit", context do
    stub(VCS, :get_run_report_sections, fn _ ->
      %{summary: String.duplicate("é", 32_768), failed_tests: nil, flaky_tests: nil}
    end)

    assert :ok = EntireTrails.sync(context.connection.id)
    [%{"body" => body}] = Agent.get(context.remote, &Map.values(&1.summaries))
    assert body =~ "[View the full report]"
    assert body =~ @sha
    assert byte_size(body) <= 65_535
    assert [%{"body" => comment}] = comments(context)
    assert String.length(comment) <= 65_536
  end

  test "stops publishing for disabled, suspended, or revoked installations", context do
    build(context.project, @sha, "App", 1)
    stub(FunWithFlags, :enabled?, fn _, _ -> false end)
    assert :ok = EntireTrails.sync(context.connection.id)
    stub(FunWithFlags, :enabled?, fn flag, _ -> flag == :entire_trails end)

    context.installation |> Ecto.Changeset.change(active: false) |> Repo.update!()
    assert :ok = EntireTrails.sync(context.connection.id)
    context.installation |> Ecto.Changeset.change(active: true) |> Repo.update!()
    Agent.update(context.remote, &%{&1 | revoked: true})
    assert :ok = EntireTrails.sync(context.connection.id)
    assert Agent.get(context.remote, & &1.writes) == 0
  end

  test "publishes actionable whole-change findings and resolves superseded findings", context do
    stub(VCS, :get_run_report_sections, fn _ ->
      %{
        summary: "Tests need attention",
        failed_tests: "LoginTests: testExpiredSession failed",
        flaky_tests: "SearchTests: testResults is flaky"
      }
    end)

    assert :ok = EntireTrails.sync(context.connection.id)
    [report] = Agent.get(context.remote, &Map.values(&1.summaries))
    assert [failed, flaky] = report["findings"]
    assert failed["severity"] == "medium"
    assert failed["body"] =~ "testExpiredSession"
    assert failed["location"] == %{"granularity" => "whole_change"}
    assert flaky["severity"] == "low"
    assert flaky["body"] =~ "testResults"
    [old] = Repo.all(Summary)
    assert length(old.finding_ids) == 2

    stub(VCS, :get_run_report_sections, fn _ ->
      %{summary: "Tests passed on retry", failed_tests: nil, flaky_tests: nil}
    end)

    assert :ok = EntireTrails.sync(context.connection.id)
    [current] = Repo.all(Summary)
    refute current.review_id == old.review_id
    assert current.finding_ids == []
    assert map_size(Agent.get(context.remote, & &1.resolved)) == 2
  end

  test "keeps project and installation connections account-scoped", context do
    other_account = AccountsFixtures.user_fixture().account
    other_project = ProjectsFixtures.project_fixture(account_id: other_account.id)
    other_installation = Repo.insert!(%Installation{account_id: other_account.id, remote_id: "ins_other"})

    assert {:error, :not_found} = EntireTrails.connect(context.account, %{context.attrs | project_id: other_project.id})

    assert {:error, :not_found} =
             EntireTrails.connect(context.account, %{context.attrs | installation_id: other_installation.id})

    assert {:error, :revoked} =
             EntireTrails.connect(context.account, %{context.attrs | repository_id: "repo_not_selected"})

    assert {:error, :not_found} = EntireTrails.disconnect(other_account, context.connection.id)
    assert EntireTrails.connections(other_account) == []
    assert [%{repository_name: "acme/app"}] = EntireTrails.connections(context.account)
    assert {:ok, [%{id: "repo_other"}, %{id: "repo_selected"}]} = EntireTrails.repositories(context.account)
  end

  test "reports ingested test failures and clears findings after a successful rerun", context do
    stub(Environment, :app_url, fn opts -> "https://tuist.dev" <> opts[:path] end)

    attrs = [
      project_id: context.project.id,
      account_id: context.account.id,
      git_commit_sha: @sha,
      git_ref: "refs/pull/13/head",
      scheme: "AppTests",
      status: "failure",
      inserted_at: ~N[2026-11-09 10:00:00],
      test_modules: [
        %{
          name: "AppTests",
          status: "failure",
          duration: 1000,
          test_cases: [%{name: "testExpiredSession", suite_name: "LoginTests", status: "failure", duration: 1000}]
        }
      ]
    ]

    RunsFixtures.test_fixture(attrs)
    assert :ok = EntireTrails.sync(context.connection.id)
    initial = Agent.get(context.remote, & &1)
    [report] = Map.values(initial.summaries)
    assert [finding] = report["findings"]
    assert finding["body"] =~ "testExpiredSession"
    assert finding["severity"] == "medium"

    assert :ok = EntireTrails.sync(context.connection.id)
    assert Agent.get(context.remote, & &1.summaries) == initial.summaries
    assert Agent.get(context.remote, & &1.checks) == initial.checks

    attrs =
      Keyword.merge(attrs,
        status: "success",
        inserted_at: ~N[2026-11-09 10:01:00],
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 800,
            test_cases: [%{name: "testExpiredSession", suite_name: "LoginTests", status: "success", duration: 800}]
          }
        ]
      )

    RunsFixtures.test_fixture(attrs)
    assert :ok = EntireTrails.sync(context.connection.id)
    final = Agent.get(context.remote, & &1)
    assert map_size(final.resolved) == 1
    [summary] = Repo.all(Summary)
    assert summary.finding_ids == []
    assert summary.report_body =~ "AppTests"
  end

  test "queues updates from serialized insight uploads and Trail events independently of CI", context do
    Repo.delete_all(Oban.Job)

    comment = %{git_commit_sha: nil, git_ref: nil, git_remote_url_origin: nil, project_id: context.project.id}

    for params <- [comment, Map.new(comment, fn {key, value} -> {to_string(key), value} end)] do
      assert {:ok, _} = VCS.enqueue_vcs_pull_request_comment(params)
    end

    # Processors enqueue the comment and cannot read Entire connections, so the
    # report is queued by the comment worker, which runs on web nodes.
    assert all_enqueued(worker: ReportWorker) == []
    stub(VCS, :post_vcs_pull_request_comment, fn _ -> :ok end)
    [comment_job] = all_enqueued(worker: CommentWorker)
    assert :ok = perform_job(CommentWorker, comment_job.args)
    assert length(all_enqueued(worker: ReportWorker)) == 1
    Repo.delete_all(Oban.Job)

    delivery = %{
      "installation_id" => context.installation.remote_id,
      "event" => %{"type" => "trail.opened", "payload" => %{"repository" => %{"id" => "repo_selected"}}}
    }

    assert :ok = perform_job(DeliveryWorker, delivery)
    assert length(all_enqueued(worker: ReportWorker)) == 1
  end

  test "late uploads retain their flush delay even when a report is already scheduled or available", context do
    Repo.delete_all(Oban.Job)
    stub(Environment, :clickhouse_flush_interval_ms, fn -> 5_000 end)

    EntireTrails.enqueue(context.project.id)
    [first] = all_enqueued(worker: ReportWorker)

    # Simulate another upload after the previous flush, just before this job runs.
    first
    |> Ecto.Changeset.change(scheduled_at: DateTime.add(DateTime.utc_now(), 1))
    |> Repo.update!()

    uploaded_at = DateTime.utc_now()
    EntireTrails.enqueue(context.project.id)
    [rescheduled] = all_enqueued(worker: ReportWorker)
    assert rescheduled.id == first.id
    assert DateTime.diff(rescheduled.scheduled_at, uploaded_at) >= 5

    # Once staged, the ready job must not absorb a still-buffered upload.
    rescheduled
    |> Ecto.Changeset.change(state: "available", scheduled_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    uploaded_at = DateTime.utc_now()
    EntireTrails.enqueue(context.project.id)
    jobs = all_enqueued(worker: ReportWorker)
    assert length(jobs) == 2
    assert Enum.any?(jobs, &(&1.id == first.id and &1.state == "available"))
    follow_up = Enum.find(jobs, &(&1.state == "scheduled"))
    assert DateTime.diff(follow_up.scheduled_at, uploaded_at) >= 5
  end

  defp build(project, sha, scheme, second) do
    RunsFixtures.build_fixture(
      project_id: project.id,
      git_commit_sha: sha,
      git_ref: "refs/pull/13/head",
      scheme: scheme,
      inserted_at: NaiveDateTime.add(~N[2026-10-27 06:00:00], second)
    )
  end

  defp request(opts, remote, installation) do
    uri = URI.parse(opts[:url])
    path = uri.path
    params = Map.new(opts[:params] || [])
    assert opts[:redirect] == false
    assert opts[:retry] == false

    cond do
      String.ends_with?(path, "/repositories") ->
        if Agent.get(remote, & &1.revoked) do
          response(404, %{})
        else
          if params[:cursor] == "repositories-2" do
            response(200, %{"repositories" => [repository("repo_selected", "acme/app")], "next_cursor" => nil})
          else
            response(200, %{"repositories" => [repository("repo_other", "acme/other")], "next_cursor" => "repositories-2"})
          end
        end

      String.ends_with?(path, "/access-tokens") ->
        %{repository_id: "repo_selected", permissions: permissions} = opts[:json]
        discussions = %{"contents" => "read", "discussions" => "write"}
        assert permissions in [%{"contents" => "read", "checks" => "write", "findings" => "write"}, discussions]

        if permissions == discussions and Agent.get(remote, & &1.deny_discussions),
          do: response(403, %{}),
          else: response(201, %{"token" => "repository-scoped"})

      true ->
        assert uri.host == URI.parse(@api).host
        assert {"authorization", "Bearer repository-scoped"} in opts[:headers]
        api_request(opts, remote, installation, path, params)
    end
  end

  defp api_request(opts, remote, installation, path, params) do
    case String.split(path, "/api/v1/repos/repo_selected/trails/7/discussions", parts: 2) do
      ["", rest] ->
        tuist = %{"kind" => "automation", "automation" => %{"installation_id" => installation.remote_id}}
        discussion_request(opts[:method], rest, opts, remote, tuist)

      _ ->
        region_request(opts, remote, path, params)
    end
  end

  defp region_request(opts, remote, path, params) do
    base = "/api/v1/repos/repo_selected/trails"

    case {opts[:method], String.replace_prefix(path, base, "")} do
      {:post, "/api/v1/repos/repo_selected/commits/" <> rest} ->
        assert rest in [@sha <> "/check-runs", @other_sha <> "/check-runs"]
        %{check_suite: suite, check_runs: [run]} = opts[:json]
        assert opts[:json][:branch] == "feature/insights"
        assert suite.status == "completed"
        assert suite.conclusion == "neutral"
        assert run.key == "report"
        assert run.output.title == "Tuist insights"
        assert byte_size(run.output.summary) <= 65_535
        assert {:ok, _, 0} = DateTime.from_iso8601(suite.external_updated_at)
        Agent.update(remote, &%{&1 | checks: Map.put(&1.checks, suite.external_id, opts[:json]), writes: &1.writes + 1})
        response(200, %{})

      {:get, ""} ->
        assert params["status"] == "open,draft"

        if params["cursor"] == "trails-2" do
          response(200, %{"items" => [%{"number" => 7}], "next_cursor" => ""})
        else
          response(200, %{"items" => [], "next_cursor" => "trails-2"})
        end

      {:get, "/7"} ->
        state = Agent.get(remote, & &1)

        response(200, %{
          "id" => "trail_stable",
          "number" => 7,
          "head_sha" => state.head,
          "branch" => "feature/insights",
          "status" => state.status
        })

      {:post, "/7/reviews"} ->
        assert opts[:json] in [%{head_sha: @sha}, %{head_sha: @other_sha}]
        key = opts[:headers] |> Map.new() |> Map.fetch!("idempotency-key")
        review_id = "review-" <> key
        Agent.update(remote, &%{&1 | reviews: Map.put(&1.reviews, key, review_id)})
        response(201, %{"review_id" => review_id})

      {:post, "/7/reviews/" <> rest} ->
        assert String.ends_with?(rest, "/comments")
        key = opts[:headers] |> Map.new() |> Map.fetch!("idempotency-key")
        message = %{"body" => opts[:json][:summary], "findings" => opts[:json][:comments]}

        lost? =
          Agent.get_and_update(
            remote,
            &{&1.fail_after_create,
             %{&1 | summaries: Map.put(&1.summaries, key, message), writes: &1.writes + 1, fail_after_create: false}}
          )

        if lost?,
          do: {:error, :closed},
          else:
            response(200, %{
              "review" => %{},
              "results" => Enum.map(opts[:json][:comments], &%{"comment" => %{"id" => key <> &1["client_id"]}})
            })

      {:patch, "/7/reviews/" <> rest} ->
        assert opts[:json][:status] == "resolved"
        assert opts[:json][:status_reason] != ""

        Agent.update(
          remote,
          &Map.update(&1, :resolved, %{rest => true}, fn resolved -> Map.put(resolved, rest, true) end)
        )

        response(200, %{})
    end
  end

  defp discussion_request(method, path, opts, remote, tuist) do
    case {method, path} do
      {:get, ""} ->
        items =
          Enum.map(Agent.get(remote, & &1.discussions), fn {id, discussion} ->
            %{"id" => id, "created_by_identity" => discussion["identity"]}
          end)

        response(200, %{"items" => items, "next_cursor" => ""})

      {:get, "/" <> id} ->
        %{"identity" => identity, "messages" => messages} = Agent.get(remote, & &1.discussions[id])
        response(200, %{"messages" => Enum.map(messages, &Map.put(&1, "identity", identity))})

      {:post, ""} ->
        id = "discussion-#{System.unique_integer([:positive])}"
        message = %{"id" => "message-" <> id, "body" => opts[:json][:body]}
        discussion = %{"identity" => tuist, "title" => opts[:json][:title], "messages" => [message]}

        lost? =
          Agent.get_and_update(
            remote,
            &{&1.lose_comment, %{&1 | discussions: Map.put(&1.discussions, id, discussion), lose_comment: false}}
          )

        if lost?,
          do: {:error, :closed},
          else: response(201, %{"discussion" => %{"id" => id}, "message" => %{"id" => message["id"]}})

      {:patch, "/" <> rest} ->
        [id, "messages", message_id] = String.split(rest, "/")

        Agent.get_and_update(remote, fn state ->
          case state.discussions[id] do
            %{"identity" => ^tuist, "messages" => [%{"id" => ^message_id} = message]} = discussion ->
              discussion = %{discussion | "messages" => [%{message | "body" => opts[:json][:body]}]}
              {response(200, %{"message" => %{"id" => message_id}}), put_in(state.discussions[id], discussion)}

            _ ->
              {response(404, %{}), state}
          end
        end)
    end
  end

  defp comments(context) do
    context.remote
    |> Agent.get(& &1.discussions)
    |> Enum.reject(fn {id, _} -> id == "human" end)
    |> Enum.map(fn {id, %{"title" => title, "messages" => [message]}} ->
      %{"id" => id, "title" => title, "body" => message["body"]}
    end)
  end

  defp repository(id, name) do
    %{
      "id" => id,
      "full_name" => name,
      "entire_clone_url" => "entire://aws-eu-central-1.entire.io/et/#{name}",
      "placements" => [
        %{"role" => "mirror", "api_base_url" => "https://wrong.api.entire.io"},
        %{"role" => "processing_primary", "api_base_url" => @api}
      ]
    }
  end

  defp response(status, body), do: {:ok, %Req.Response{status: status, body: body}}
end
