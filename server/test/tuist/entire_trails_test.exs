defmodule Tuist.EntireTrailsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Entire.Client, as: Entire
  alias Tuist.Entire.Installation
  alias Tuist.Entire.Workers.DeliveryWorker
  alias Tuist.EntireTrails
  alias Tuist.EntireTrails.Summary
  alias Tuist.EntireTrails.Workers.ReportWorker
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.VCS
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
        %{head: @sha, status: "open", summaries: [], writes: 0, fail_after_create: false, revoked: false}
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

  test "publishes current-commit insights, updates one summary, and recovers lost pointers", context do
    build(context.project, @sha, "Current", 1)
    build(context.project, @other_sha, "Stale", 2)

    assert :ok = EntireTrails.sync(context.connection.id)
    [summary] = Agent.get(context.remote, & &1.summaries)
    assert summary["body"] =~ "Current"
    refute summary["body"] =~ "Stale"
    assert summary["body"] =~ "`aaaaaaaaa`"
    refute summary["body"] =~ "/commit/"
    assert summary["body"] =~ "/#{context.account.name}/#{context.project.name}/builds/build-runs/"

    build(context.project, @sha, "Later", 3)
    assert :ok = EntireTrails.sync(context.connection.id)
    assert [%{"body" => body}] = Agent.get(context.remote, & &1.summaries)
    assert body =~ "Current"
    assert body =~ "Later"

    Repo.delete_all(Summary)
    assert :ok = EntireTrails.sync(context.connection.id)
    assert length(Agent.get(context.remote, & &1.summaries)) == 1
    assert Repo.aggregate(Summary, :count) == 1

    assert {:ok, _} = EntireTrails.disconnect(context.account, context.connection.id)
    assert Repo.aggregate(Summary, :count) == 0
    assert :ok = EntireTrails.sync(context.connection.id)
    assert length(Agent.get(context.remote, & &1.summaries)) == 1
  end

  test "recovers a successful create whose response was lost without posting a duplicate", context do
    build(context.project, @sha, "App", 1)
    Agent.update(context.remote, &%{&1 | fail_after_create: true})

    assert {:error, :unavailable} = EntireTrails.sync(context.connection.id)
    assert Repo.aggregate(Summary, :count) == 0
    assert :ok = EntireTrails.sync(context.connection.id)
    assert length(Agent.get(context.remote, & &1.summaries)) == 1
    assert Repo.aggregate(Summary, :count) == 1
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

    stub(VCS, :get_run_report, fn _ ->
      Agent.update(context.remote, &%{&1 | head: @other_sha})
      "Old results"
    end)

    assert :ok = EntireTrails.sync(context.connection.id)
    assert Agent.get(context.remote, & &1.writes) == 0
  end

  test "links to Tuist when the report exceeds Entire's message limit", context do
    # The report fits by itself, but the recovery marker pushes it over the limit.
    stub(VCS, :get_run_report, fn _ -> String.duplicate("x", 65_536) end)
    assert :ok = EntireTrails.sync(context.connection.id)
    [%{"body" => body}] = Agent.get(context.remote, & &1.summaries)
    assert body =~ "[View the full report]"
    assert body =~ @sha
    assert body =~ "<!-- tuist-project:#{context.project.id} -->"
    assert String.length(body) <= 65_536
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

  test "queues updates from serialized insight uploads and Trail events independently of CI", context do
    Repo.delete_all(Oban.Job)

    for params <- [%{project_id: context.project.id}, %{"project_id" => context.project.id}] do
      assert {:ok, _} = VCS.enqueue_vcs_pull_request_comment(params)
    end

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
        assert opts[:json] == %{
                 repository_id: "repo_selected",
                 permissions: %{"contents" => "read", "discussions" => "write"}
               }

        response(201, %{"token" => "repository-scoped"})

      true ->
        assert uri.host == URI.parse(@api).host
        assert opts[:headers] == [{"authorization", "Bearer repository-scoped"}]
        region_request(opts, remote, installation, path, params)
    end
  end

  defp region_request(opts, remote, installation, path, params) do
    base = "/api/v1/repos/repo_selected/trails"

    case {opts[:method], String.replace_prefix(path, base, "")} do
      {:get, ""} ->
        assert params["status"] == "open,draft"

        if params["cursor"] == "trails-2" do
          response(200, %{"items" => [%{"number" => 7}], "next_cursor" => ""})
        else
          response(200, %{"items" => [], "next_cursor" => "trails-2"})
        end

      {:get, "/7"} ->
        state = Agent.get(remote, & &1)
        response(200, %{"id" => "trail_stable", "number" => 7, "head_sha" => state.head, "status" => state.status})

      {:get, "/7/discussions"} ->
        discussion_page(remote, installation, params)

      {:get, "/7/discussions/summary"} ->
        response(200, %{"messages" => Agent.get(remote, & &1.summaries)})

      {:post, "/7/discussions"} ->
        message = %{"id" => "summary", "body" => opts[:json][:body], "identity" => identity(installation.remote_id)}

        lost? =
          Agent.get_and_update(
            remote,
            &{&1.fail_after_create,
             %{&1 | summaries: &1.summaries ++ [message], writes: &1.writes + 1, fail_after_create: false}}
          )

        if lost?,
          do: {:error, :closed},
          else: response(201, %{"discussion" => %{"id" => "summary"}, "message" => message})

      {:patch, "/7/discussions/summary/messages/summary"} ->
        Agent.update(remote, fn state ->
          %{
            state
            | summaries: Enum.map(state.summaries, &Map.put(&1, "body", opts[:json][:body])),
              writes: state.writes + 1
          }
        end)

        response(200, %{})
    end
  end

  defp discussion_page(remote, installation, %{"cursor" => "discussions-2"}) do
    discussions =
      Enum.map(
        Agent.get(remote, & &1.summaries),
        &%{"id" => &1["id"], "created_by_identity" => identity(installation.remote_id)}
      )

    response(200, %{"items" => discussions})
  end

  defp discussion_page(_remote, _installation, _params) do
    # A different installation's similarly named comment must not be edited.
    response(200, %{
      "items" => [%{"id" => "foreign", "created_by_identity" => identity("ins_foreign")}],
      "next_cursor" => "discussions-2"
    })
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

  defp identity(id), do: %{"kind" => "automation", "automation" => %{"installation_id" => id}}
  defp response(status, body), do: {:ok, %Req.Response{status: status, body: body}}
end
