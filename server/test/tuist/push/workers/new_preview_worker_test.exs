defmodule Tuist.Push.Workers.NewPreviewWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Notifications
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Push
  alias Tuist.Push.Workers.DeliveryWorker
  alias Tuist.Push.Workers.NewPreviewWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    app_client_id = Ecto.UUID.generate()
    stub(Environment, :oauth_client_id, fn -> app_client_id end)
    stub(Environment, :apns_configured?, fn -> true end)

    creator = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: creator)
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account: account)

    %{client: Clients.public!(), creator: creator, organization: organization, account: account, project: project}
  end

  defp register(user, client, platform) do
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client.id})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: ""
    })

    {:ok, session} = Push.oauth_session(bearer, user)

    device =
      case platform do
        "ios" ->
          %{platform: "ios", token: Base.encode16(:crypto.strong_rand_bytes(32)), environment: "production"}

        "android" ->
          %{platform: "android", token: Base.encode64(:crypto.strong_rand_bytes(32)), environment: "production"}
      end

    {:ok, installation} = Push.register(user, session, Ecto.UUID.generate(), device)
    installation
  end

  defp enqueued_registration_ids do
    [worker: DeliveryWorker] |> all_enqueued() |> Enum.map(& &1.args["registration_id"]) |> Enum.sort()
  end

  test "sends to the iOS devices of members who want the project's previews", %{
    client: client,
    creator: creator,
    organization: organization,
    account: account,
    project: project
  } do
    wants = AccountsFixtures.user_fixture()
    opted_out = AccountsFixtures.user_fixture()
    outsider = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(wants, organization)
    Accounts.add_user_to_organization(opted_out, organization)

    creator_device = register(creator, client, "ios")
    wants_device = register(wants, client, "ios")
    register(wants, client, "android")
    register(opted_out, client, "ios")
    register(outsider, client, "ios")
    :ok = Notifications.update_project_preference(opted_out, "new_preview", project.id, false)

    preview = AppBuildsFixtures.preview_fixture(project: project, display_name: "TuistApp", version: "1.2")

    assert :ok = perform_job(NewPreviewWorker, %{"preview_id" => preview.id})

    assert enqueued_registration_ids() == Enum.sort([creator_device.id, wants_device.id])

    [job | _] = all_enqueued(worker: DeliveryWorker)

    assert job.args["payload"] == %{
             "aps" => %{
               "alert" => %{
                 "title" => "TuistApp",
                 "subtitle" => "#{account.name}/#{project.name}",
                 "body" => "Version 1.2 is ready to install."
               },
               "sound" => "default",
               "thread-id" => "#{account.name}/#{project.name}"
             },
             "preview_id" => preview.id,
             "account_handle" => account.name,
             "project_handle" => project.name
           }
  end

  test "sends a personal project's previews to its owner only", %{client: client} do
    owner = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    owner_device = register(owner, client, "ios")
    register(other, client, "ios")
    project = ProjectsFixtures.project_fixture(account: Accounts.get_account_from_user(owner))
    preview = AppBuildsFixtures.preview_fixture(project: project)

    assert :ok = perform_job(NewPreviewWorker, %{"preview_id" => preview.id})

    assert enqueued_registration_ids() == [owner_device.id]
  end

  test "doesn't notify about a build uploaded to a preview older than a day", %{
    client: client,
    creator: creator,
    project: project
  } do
    register(creator, client, "ios")

    preview =
      AppBuildsFixtures.preview_fixture(project: project, inserted_at: DateTime.add(DateTime.utc_now(), -25, :hour))

    assert :ok = perform_job(NewPreviewWorker, %{"preview_id" => preview.id})

    assert enqueued_registration_ids() == []
  end

  describe "Push.notify_new_preview/1" do
    test "queues one notification per preview however many builds upload", %{project: project} do
      preview = AppBuildsFixtures.preview_fixture(project: project)

      :ok = Push.notify_new_preview(preview)
      :ok = Push.notify_new_preview(preview)

      assert [%{args: %{"preview_id" => preview_id}}] = all_enqueued(worker: NewPreviewWorker)
      assert preview_id == preview.id
    end

    test "does nothing without an APNs key", %{project: project} do
      stub(Environment, :apns_configured?, fn -> false end)

      :ok = Push.notify_new_preview(AppBuildsFixtures.preview_fixture(project: project))

      refute_enqueued(worker: NewPreviewWorker)
    end
  end
end
