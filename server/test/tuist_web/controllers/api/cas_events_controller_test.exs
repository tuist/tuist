defmodule TuistWeb.API.CASEventsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Cache.CASEvent
  alias Tuist.IngestRepo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @cache_api_key "test-cache-api-key"

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    conn = assign(conn, :selected_project, project)

    stub(Tuist.Environment, :cache_api_key, fn -> @cache_api_key end)

    %{conn: conn, user: user, project: project}
  end

  defp sign_request(body) do
    json_body = Jason.encode!(body)

    signature =
      :hmac
      |> :crypto.mac(:sha256, @cache_api_key, json_body)
      |> Base.encode16(case: :lower)

    {json_body, signature}
  end

  describe "POST /api/projects/:account_handle/:project_handle/cache/cas/events" do
    test "creates multiple CAS events", %{conn: conn, project: project} do
      # Given
      events_params = %{
        "events" => [
          %{
            "action" => "upload",
            "size" => 1024,
            "cas_id" => "abc123"
          },
          %{
            "action" => "download",
            "size" => 2048,
            "cas_id" => "def456"
          },
          %{
            "action" => "upload",
            "size" => 512,
            "cas_id" => "ghi789"
          }
        ]
      }

      {body, signature} = sign_request(events_params)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-signature", signature)
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/cache/cas/events",
          body
        )

      # Then
      assert json_response(conn, 202) == %{}

      # Verify all events were created in database
      events =
        IngestRepo.all(from e in CASEvent, where: e.project_id == ^project.id, order_by: e.size)

      assert length(events) == 3

      [event1, event2, event3] = events

      assert event1.action == "upload"
      assert event1.size == 512
      assert event1.cas_id == "ghi789"

      assert event2.action == "upload"
      assert event2.size == 1024
      assert event2.cas_id == "abc123"

      assert event3.action == "download"
      assert event3.size == 2048
      assert event3.cas_id == "def456"
    end
  end
end
