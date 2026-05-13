defmodule Tuist.Webhooks.DispatcherTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.IngestRepo
  alias Tuist.Tests.TestCase
  alias Tuist.Webhooks
  alias Tuist.Webhooks.Dispatcher
  alias Tuist.Webhooks.Workers.DeliveryWorker
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  defp insert_test_case(project, attrs \\ []) do
    test_case = RunsFixtures.test_case_fixture([project_id: project.id] ++ attrs)
    IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])
    test_case
  end

  describe "dispatch_test_case_event/3" do
    test "enqueues a DeliveryWorker job per matching endpoint" do
      project = ProjectsFixtures.project_fixture()

      {:ok, subscribed, _} =
        Webhooks.create_endpoint(project.account_id, %{
          "name" => "Jira",
          "url" => "https://example.com/hook",
          "event_types" => ["test_case.updated"]
        })

      test_case = insert_test_case(project, is_flaky: true, state: "muted")

      assert :ok = Dispatcher.dispatch_test_case_event(test_case, [:marked_flaky, :muted])

      [job] = Tuist.Repo.all(Oban.Job)
      assert job.worker == inspect(DeliveryWorker)
      assert job.args["webhook_endpoint_id"] == subscribed.id
      assert job.args["event_type"] == "test_case.updated"

      payload = job.args["payload"]
      assert payload["type"] == "test_case.updated"
      assert payload["events"] == ["marked_flaky", "muted"]
      assert payload["object"]["id"] == test_case.id
      assert payload["object"]["is_flaky"] == true
      assert payload["object"]["state"] == "muted"
      assert payload["endpoint"]["id"] == subscribed.id
      assert payload["account"]["id"] == project.account_id
    end

    test "skips endpoints in other accounts" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()

      {:ok, _other_endpoint, _} =
        Webhooks.create_endpoint(other_project.account_id, %{
          "name" => "Other",
          "url" => "https://example.com/other",
          "event_types" => ["test_case.updated"]
        })

      test_case = insert_test_case(project)

      assert :ok = Dispatcher.dispatch_test_case_event(test_case, [:marked_flaky])
      assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
    end

    test "no-ops when no endpoints are subscribed" do
      project = ProjectsFixtures.project_fixture()
      test_case = insert_test_case(project)

      assert :ok = Dispatcher.dispatch_test_case_event(test_case, [:marked_flaky])
      assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
    end

    test "forwards actor_id and alert_id when supplied" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _endpoint, _} =
        Webhooks.create_endpoint(project.account_id, %{
          "name" => "Hook",
          "url" => "https://example.com/hook",
          "event_types" => ["test_case.updated"]
        })

      test_case = insert_test_case(project)
      alert_id = Ecto.UUID.generate()

      assert :ok =
               Dispatcher.dispatch_test_case_event(test_case, [:muted],
                 actor_id: 42,
                 alert_id: alert_id
               )

      [job] = Tuist.Repo.all(Oban.Job)
      assert job.args["payload"]["actor_id"] == 42
      assert job.args["payload"]["alert_id"] == alert_id
    end
  end

  describe "dispatch_test_case_created/2" do
    test "enqueues one delivery per (endpoint, new test case) pair" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _endpoint, _} =
        Webhooks.create_endpoint(project.account_id, %{
          "name" => "Hook",
          "url" => "https://example.com/hook",
          "event_types" => ["test_case.created"]
        })

      a = RunsFixtures.test_case_fixture(project_id: project.id)
      b = RunsFixtures.test_case_fixture(project_id: project.id)

      assert :ok = Dispatcher.dispatch_test_case_created(project.id, [a, b])

      jobs = Tuist.Repo.all(Oban.Job)
      assert length(jobs) == 2
      assert Enum.all?(jobs, &(&1.args["event_type"] == "test_case.created"))
      ids = jobs |> Enum.map(& &1.args["payload"]["object"]["id"]) |> Enum.sort()
      assert ids == Enum.sort([a.id, b.id])
    end

    test "no-ops when the new-test-case list is empty" do
      project = ProjectsFixtures.project_fixture()
      assert :ok = Dispatcher.dispatch_test_case_created(project.id, [])
      assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
    end
  end

  describe "dispatch_preview_deleted/1" do
    test "enqueues a preview.deleted delivery for each subscribed endpoint" do
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)

      {:ok, _endpoint, _} =
        Webhooks.create_endpoint(project.account_id, %{
          "name" => "Hook",
          "url" => "https://example.com/hook",
          "event_types" => ["preview.deleted"]
        })

      assert :ok = Dispatcher.dispatch_preview_deleted(preview)

      [job] = Tuist.Repo.all(Oban.Job)
      assert job.args["event_type"] == "preview.deleted"
      assert job.args["payload"]["object"]["id"] == preview.id
    end
  end

  describe "dispatch_preview_uploaded/1" do
    test "enqueues a preview.uploaded delivery for each subscribed endpoint" do
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)

      {:ok, subscribed, _} =
        Webhooks.create_endpoint(project.account_id, %{
          "name" => "Jira",
          "url" => "https://example.com/hook",
          "event_types" => ["preview.uploaded"]
        })

      assert :ok = Dispatcher.dispatch_preview_uploaded(preview)

      [job] = Tuist.Repo.all(Oban.Job)
      assert job.args["webhook_endpoint_id"] == subscribed.id
      assert job.args["event_type"] == "preview.uploaded"

      payload = job.args["payload"]
      assert payload["type"] == "preview.uploaded"
      assert payload["object"]["id"] == preview.id
      assert payload["object"]["project_id"] == project.id
    end

    test "no-ops when no endpoints subscribe to preview.uploaded" do
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)

      # A `test_case.updated` subscriber must be skipped here.
      {:ok, _other, _} =
        Webhooks.create_endpoint(project.account_id, %{
          "name" => "Other",
          "url" => "https://example.com/hook",
          "event_types" => ["test_case.updated"]
        })

      assert :ok = Dispatcher.dispatch_preview_uploaded(preview)
      assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
    end
  end
end
