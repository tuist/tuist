defmodule Tuist.OnceEvents.AuthenticationAvailabilityTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Once.Events.V1.GetArgvHashKeyRequest
  alias Tuist.Accounts
  alias Tuist.Authentication.TokenVerificationCache
  alias Tuist.Authentication.UnavailableError
  alias Tuist.OnceEvents.RunEventService
  alias Tuist.Projects
  alias Tuist.Telemetry
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.TelemetryCapture

  setup :set_mimic_global

  defmodule HeadersAdapter do
    @moduledoc false
    def get_headers(headers), do: headers
  end

  for kind <- [:project, :account] do
    @kind kind
    test "Once #{@kind} proof failure refuses as unavailable and records telemetry" do
      project = ProjectsFixtures.project_fixture()
      token = credential(@kind, project)
      expect(TokenVerificationCache, :verify_pass, 1, fn _, _ -> raise UnavailableError end)
      event = Telemetry.event_name_once_events_refused()
      ref = TelemetryCapture.attach_event_handlers([event])
      stream = %GRPC.Server.Stream{adapter: HeadersAdapter, payload: %{"authorization" => "Bearer " <> token}}
      request = %GetArgvHashKeyRequest{project_id: "#{project.account.name}/#{project.name}"}

      error = assert_raise GRPC.RPCError, fn -> RunEventService.get_argv_hash_key(request, stream) end
      assert error.status == GRPC.Status.unavailable()
      assert_receive {^event, ^ref, %{count: 1}, %{status: :unavailable, stage: :admission}}
    end
  end

  defp credential(:project, project), do: Projects.create_project_token(project)

  defp credential(:account, project) do
    {:ok, {_, token}} =
      Accounts.create_account_token(%{
        account: project.account,
        scopes: ["project:cache:write"],
        name: "unavailable-once",
        all_projects: true
      })

    token
  end
end
