defmodule AtlasWeb.ErrorsAPI.EnvelopeControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.Availability
  alias Atlas.Engineering.Projects

  setup :verify_on_exit!

  setup %{conn: conn} do
    stub(Availability, :enabled?, fn -> true end)
    stub(Errors, :ingest_envelope, fn _project, _body, _opts -> :ok end)

    {:ok, project} = Projects.create_project(%{"name" => "Widgets", "visibility" => "public"})
    {:ok, key} = Errors.create_project_key(project.id)

    conn =
      conn
      |> put_req_header("content-type", "application/x-sentry-envelope")
      |> put_req_header(
        "x-sentry-auth",
        "Sentry sentry_version=7, sentry_key=#{key.public_key}"
      )

    {:ok, conn: conn, project: project, key: key}
  end

  describe "POST /api/:project_id/envelope/" do
    test "accepts a valid event envelope at the numeric project id", %{conn: conn, key: key} do
      test_pid = self()

      expect(Errors, :ingest_envelope, fn _project, body, _opts ->
        send(test_pid, {:ingested, body})
        :ok
      end)

      body =
        envelope_body(
          "evt-abc-1234567890abcdef1234567890",
          ~s({"level":"error","message":"boom"})
        )

      conn = post(conn, ~p"/api/#{key.dsn_project_id}/envelope/", body)

      assert %{"id" => id} = json_response(conn, 200)
      assert is_binary(id)

      assert_received {:ingested, ^body}
    end

    test "rejects requests missing sentry_key", %{project: project} do
      body = envelope_body("evt-xyz", ~s({"level":"error"}))

      conn =
        build_conn()
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post(~p"/api/#{project.id}/envelope/", body)

      assert conn.status == 401
    end

    test "rejects requests whose key belongs to a different project", %{conn: conn} do
      {:ok, other} = Projects.create_project(%{"name" => "Other", "visibility" => "public"})
      {:ok, other_key} = Errors.create_project_key(other.id)
      body = envelope_body("evt-y", ~s({"level":"error"}))

      conn = post(conn, ~p"/api/#{other_key.dsn_project_id}/envelope/", body)
      assert conn.status == 403
    end

    test "accepts inline even when ClickHouse is disabled", %{conn: conn, key: key} do
      stub(Availability, :enabled?, fn -> false end)
      body = envelope_body("evt-z", ~s({"level":"error"}))

      conn = post(conn, ~p"/api/#{key.dsn_project_id}/envelope/", body)
      assert conn.status == 200
    end

    test "forwards the domain_id from a domain-scoped DSN to ingest_envelope",
         %{conn: base_conn, project: project} do
      {:ok, domain} =
        Domains.create_domain(%{"name" => "Registry", "visibility" => "public"})

      :ok = Domains.link_domain_to_project(domain, project.id)
      {:ok, domain_key} = Errors.create_domain_key(project.id, domain.id)
      test_pid = self()

      expect(Errors, :ingest_envelope, fn _project, _body, opts ->
        send(test_pid, {:ingested_with, Keyword.get(opts, :domain_id)})
        :ok
      end)

      conn =
        base_conn
        |> Plug.Conn.delete_req_header("x-sentry-auth")
        |> put_req_header(
          "x-sentry-auth",
          "Sentry sentry_version=7, sentry_key=#{domain_key.public_key}"
        )

      body = envelope_body("evt-domain", ~s({"level":"error"}))
      conn = post(conn, ~p"/api/#{domain_key.dsn_project_id}/envelope/", body)
      domain_id = domain.id

      assert conn.status == 200
      assert_received {:ingested_with, ^domain_id}
    end
  end

  defp envelope_body(event_id, payload) do
    [
      ~s({"event_id":"#{event_id}","sent_at":"2026-09-03T15:00:00Z"}),
      ~s({"type":"event","length":#{byte_size(payload)}}),
      payload
    ]
    |> Enum.join("\n")
  end
end
