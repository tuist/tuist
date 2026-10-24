defmodule Atlas.Push.Workers.DeliverTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  import Atlas.PushFixtures
  import Atlas.TimeOffFixtures, only: [user_fixture: 0]

  alias Atlas.Audit.Activity
  alias Atlas.Authorization.Roles
  alias Atlas.Orbit
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Thread
  alias Atlas.Push
  alias Atlas.Push.Config
  alias Atlas.Push.Installation
  alias Atlas.Push.Workers.Deliver
  alias AtlasWeb.NativeLinks
  alias Boruta.Ecto.Token

  setup do
    test_pid = self()
    apns = apns_config()
    fcm = fcm_config()
    responses = :ets.new(:push_responses, [:public])

    stub(Config, :apns, fn -> {:ok, apns} end)
    stub(Config, :fcm, fn -> {:ok, fcm} end)
    stub(Config, :capabilities, fn -> %{"ios" => true, "android" => true} end)
    stub(Config, :available?, fn _platform, _environment -> true end)
    stub(NativeLinks.Config, :origin, fn -> "https://atlas.example.com" end)

    stub(Config, :req_options, fn ->
      [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test_pid, {:request, conn.host, conn.request_path, conn.req_headers, body})

          {status, headers, response} =
            case :ets.lookup(responses, conn.host) do
              [{_, [next | rest]}] ->
                :ets.insert(responses, {conn.host, rest})
                next

              _ ->
                {200, [], %{}}
            end

          conn = Enum.reduce(headers, conn, fn {k, v}, conn -> Plug.Conn.put_resp_header(conn, k, v) end)
          Req.Test.json(Plug.Conn.put_status(conn, status), response)
        end
      ]
    end)

    user = user_fixture()
    %{user: user, responses: responses, apns: apns}
  end

  defp respond(responses, host, list), do: :ets.insert(responses, {host, list})

  defp register(user, device) do
    {:ok, installation} = Push.register(user, native_client_id(user), Ecto.UUID.generate(), device)
    installation
  end

  defp args(installation, overrides \\ %{}) do
    Map.merge(
      %{
        "registration_id" => installation.id,
        "user_id" => installation.user_id,
        "notification_id" => Ecto.UUID.generate(),
        "kind" => "self_test",
        "screen" => "tasks",
        "record_id" => "0b6b9c2e-8f8e-4b1e-9a51-1f3d2b7f0c11",
        "expires_at" => DateTime.utc_now() |> DateTime.add(600) |> DateTime.to_iso8601()
      },
      overrides
    )
  end

  describe "APNs" do
    test "sends a generic alert to the stored environment with a signed provider token", %{user: user, apns: apns} do
      token = ios_token()
      installation = register(user, ios_device(%{"token" => token, "environment" => "sandbox"}))
      job_args = args(installation)

      assert :ok = perform_job(Deliver, job_args)

      assert_received {:request, "api.sandbox.push.apple.com", path, headers, body}
      assert path == "/3/device/" <> token
      headers = Map.new(headers)
      assert headers["apns-topic"] == "dev.tuist.atlas"
      assert headers["apns-push-type"] == "alert"
      assert headers["apns-collapse-id"] == job_args["notification_id"]

      "bearer " <> jwt = headers["authorization"]
      public = apns.private_key |> JOSE.JWK.from_pem() |> JOSE.JWK.to_public()

      assert {true, %JOSE.JWT{fields: %{"iss" => "TEAM123456"}}, %JOSE.JWS{alg: {_, :ES256}}} =
               JOSE.JWT.verify(public, jwt)

      assert JOSE.JWT.peek_protected(jwt).fields["kid"] == apns.key_id

      assert JSON.decode!(body) == %{
               "aps" => %{
                 "alert" => %{"title" => "Atlas", "body" => "You have a new notification"},
                 "sound" => "default"
               },
               "schema_version" => 1,
               "registration_id" => installation.id,
               "url" =>
                 "dev.tuist.atlas://navigate/tasks/0b6b9c2e-8f8e-4b1e-9a51-1f3d2b7f0c11?server=https%3A%2F%2Fatlas.example.com"
             }

      # The provider token is cached rather than re-signed per delivery.
      assert :ok = perform_job(Deliver, args(installation))
      assert_received {:request, _, _, second_headers, _}
      assert Map.new(second_headers)["authorization"] == "bearer " <> jwt
    end

    test "production-only credentials never contact sandbox or retire its device", %{user: user, apns: apns} do
      installation = register(user, ios_device(%{"environment" => "sandbox"}))
      stub(Config, :apns, fn -> {:ok, %{apns | environment: "production"}} end)

      assert {:cancel, :apns_not_configured} = perform_job(Deliver, args(installation))
      refute_received {:request, _, _, _, _}
      assert Repo.reload!(installation).retired_at == nil
    end

    test "retires a definitively unregistered token", %{user: user, responses: responses} do
      installation = register(user, ios_device())
      later = DateTime.utc_now() |> DateTime.add(60) |> DateTime.to_unix(:millisecond)
      respond(responses, "api.push.apple.com", [{410, [], %{"reason" => "Unregistered", "timestamp" => later}}])

      assert {:cancel, :token_invalidated} = perform_job(Deliver, args(installation))
      assert %{retired_reason: "provider_invalidated", token: nil} = Repo.reload!(installation)
    end

    test "keeps a token refreshed after Apple's unregistration timestamp", %{user: user, responses: responses} do
      installation = register(user, ios_device())
      earlier = installation.last_registered_at |> DateTime.add(-60) |> DateTime.to_unix(:millisecond)
      respond(responses, "api.push.apple.com", [{410, [], %{"reason" => "Unregistered", "timestamp" => earlier}}])

      assert {:cancel, :token_rejected_after_refresh} = perform_job(Deliver, args(installation))
      assert Repo.reload!(installation).retired_at == nil
    end

    test "BadDeviceToken retires, configuration errors do not", %{user: user, responses: responses} do
      bad = register(user, ios_device())
      topic = register(user, ios_device())

      respond(responses, "api.push.apple.com", [
        {400, [], %{"reason" => "BadDeviceToken"}},
        {400, [], %{"reason" => "DeviceTokenNotForTopic"}},
        {403, [], %{"reason" => "InvalidProviderToken"}}
      ])

      assert {:cancel, :token_invalidated} = perform_job(Deliver, args(bad))
      assert {:cancel, :apns_rejected} = perform_job(Deliver, args(topic))
      assert {:cancel, :apns_credentials_rejected} = perform_job(Deliver, args(topic))
      assert Repo.reload!(bad).retired_reason == "provider_invalidated"
      assert Repo.reload!(topic).retired_at == nil
    end

    test "retries throttling and outages within the notification lifetime", %{user: user, responses: responses} do
      installation = register(user, ios_device())

      respond(responses, "api.push.apple.com", [
        {429, [{"retry-after", "30"}], %{"reason" => "TooManyRequests"}},
        {503, [], %{"reason" => "ServiceUnavailable"}},
        {429, [{"retry-after", "3600"}], %{"reason" => "TooManyRequests"}},
        {403, [], %{"reason" => "ExpiredProviderToken"}}
      ])

      assert {:snooze, 30} = perform_job(Deliver, args(installation))
      assert {:error, :provider_unavailable} = perform_job(Deliver, args(installation))
      assert {:cancel, :expired} = perform_job(Deliver, args(installation))
      assert {:error, :provider_unavailable} = perform_job(Deliver, args(installation))
      assert Repo.reload!(installation).retired_at == nil
    end
  end

  describe "FCM" do
    test "sends a data-only message and reuses the OAuth access token", %{user: user, responses: responses} do
      token = android_token()
      installation = register(user, android_device(%{"token" => token}))
      respond(responses, "oauth2.googleapis.com", [{200, [], %{"access_token" => "fcm-access", "expires_in" => 3599}}])

      job_args = args(installation, %{"record_id" => nil, "screen" => "profile"})
      assert :ok = perform_job(Deliver, job_args)
      assert :ok = perform_job(Deliver, args(installation, %{"record_id" => nil, "screen" => "profile"}))

      assert_received {:request, "oauth2.googleapis.com", "/token", _, form}
      assert %{"grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion" => _} = URI.decode_query(form)
      refute_received {:request, "oauth2.googleapis.com", _, _, _}

      assert_received {:request, "fcm.googleapis.com", "/v1/projects/atlas-test-project/messages:send", headers, body}
      assert Map.new(headers)["authorization"] == "Bearer fcm-access"

      assert %{"message" => %{"token" => ^token, "data" => data, "android" => android}} = JSON.decode!(body)

      assert data == %{
               "schema_version" => "1",
               "title" => "Atlas",
               "body" => "You have a new notification",
               "registration_id" => installation.id,
               "notification_id" => job_args["notification_id"],
               "url" => "dev.tuist.atlas://navigate/profile?server=https%3A%2F%2Fatlas.example.com"
             }

      refute Map.has_key?(JSON.decode!(body)["message"], "notification")
      assert %{"priority" => "HIGH", "ttl" => ttl} = android
      refute Map.has_key?(android, "collapse_key")
      assert ttl =~ ~r/\A\d+s\z/
    end

    test "prunes only definitive token errors", %{user: user, responses: responses} do
      unregistered = register(user, android_device())
      mismatched = register(user, android_device())
      token_argument = register(user, android_device())
      payload_bug = register(user, android_device())

      fcm_error = fn status, code, extra ->
        {status, [],
         %{
           "error" => %{
             "details" => [
               %{"@type" => "type.googleapis.com/google.firebase.fcm.v1.FcmError", "errorCode" => code} | extra
             ]
           }
         }}
      end

      violation = fn field ->
        [%{"@type" => "type.googleapis.com/google.rpc.BadRequest", "fieldViolations" => [%{"field" => field}]}]
      end

      respond(responses, "oauth2.googleapis.com", [{200, [], %{"access_token" => "fcm-access", "expires_in" => 3599}}])

      respond(responses, "fcm.googleapis.com", [
        fcm_error.(404, "UNREGISTERED", []),
        fcm_error.(403, "SENDER_ID_MISMATCH", []),
        fcm_error.(400, "INVALID_ARGUMENT", violation.("message.token")),
        fcm_error.(400, "INVALID_ARGUMENT", violation.("message.data"))
      ])

      for installation <- [unregistered, mismatched, token_argument] do
        assert {:cancel, :token_invalidated} = perform_job(Deliver, args(installation))
        assert Repo.reload!(installation).retired_reason == "provider_invalidated"
      end

      assert {:cancel, :fcm_rejected} = perform_job(Deliver, args(payload_bug))
      assert Repo.reload!(payload_bug).retired_at == nil
    end

    test "drops a rejected access token and retries", %{user: user, responses: responses} do
      installation = register(user, android_device())

      respond(responses, "oauth2.googleapis.com", [
        {200, [], %{"access_token" => "first", "expires_in" => 3599}},
        {200, [], %{"access_token" => "second", "expires_in" => 3599}}
      ])

      respond(responses, "fcm.googleapis.com", [{401, [], %{}}, {200, [], %{}}])

      assert {:error, :provider_unavailable} = perform_job(Deliver, args(installation))
      assert :ok = perform_job(Deliver, args(installation))

      assert_received {:request, "fcm.googleapis.com", _, first, _}
      assert_received {:request, "fcm.googleapis.com", _, second, _}
      assert Map.new(first)["authorization"] == "Bearer first"
      assert Map.new(second)["authorization"] == "Bearer second"
    end
  end

  describe "Orbit completion" do
    test "delivers the exact completed run context, never a later reply", %{user: user, responses: responses} do
      {:ok, thread} = Orbit.create_shared(user, %{"title" => "Quarterly review"})
      installation = register(user, ios_device())
      reply = orbit_reply(thread, user.id, "**First reply** is [ready](https://example.org/report).")
      job_args = queued_orbit_args(installation, thread, reply)
      orbit_reply(thread, user.id, "Later unrelated reply")

      assert :ok = perform_job(Deliver, job_args)
      assert_received {:request, "api.push.apple.com", _, _, body}

      assert JSON.decode!(body) == %{
               "aps" => %{
                 "alert" => %{"title" => "Quarterly review", "subtitle" => "Pip", "body" => "First reply is ready."},
                 "sound" => "default",
                 "category" => "ATLAS_ORBIT_COMPLETED",
                 "thread-id" => thread.id
               },
               "schema_version" => 1,
               "registration_id" => installation.id,
               "url" => "dev.tuist.atlas://navigate/orbit/#{thread.id}?server=https%3A%2F%2Fatlas.example.com"
             }

      android = register(user, android_device())
      respond(responses, "oauth2.googleapis.com", [{200, [], %{"access_token" => "fcm-access", "expires_in" => 3599}}])
      android_args = queued_orbit_args(android, thread, reply)
      assert :ok = perform_job(Deliver, android_args)
      assert_received {:request, "fcm.googleapis.com", _, _, android_body}
      data = JSON.decode!(android_body)["message"]["data"]
      assert data["title"] == "Quarterly review" and data["body"] == "First reply is ready."
      assert data["url"] == "dev.tuist.atlas://navigate/orbit/#{thread.id}?server=https%3A%2F%2Fatlas.example.com"
      refute android_body =~ "Later unrelated reply"
      refute inspect(all_enqueued(worker: Deliver)) =~ "First reply"
      refute inspect(all_enqueued(worker: Deliver)) =~ "Quarterly review"
      refute inspect(Repo.all(Activity)) =~ "First reply"
      refute inspect(Repo.all(from(a in Activity, where: like(a.action, "push_%")))) =~ "Quarterly review"
    end

    test "bounds and cleans context before either provider receives it", %{user: user} do
      {:ok, thread} = Orbit.create_shared(user, %{"title" => String.duplicate("é", 100)})
      installation = register(user, ios_device())

      text =
        "```json\nraw tool evidence\n```\n# **Summary** <b>done</b>\u202e\u0001\n" <> String.duplicate("e\u0301", 200)

      reply = orbit_reply(thread, user.id, text)
      assert :ok = perform_job(Deliver, queued_orbit_args(installation, thread, reply))
      assert_received {:request, "api.push.apple.com", _, _, body}
      alert = JSON.decode!(body)["aps"]["alert"]
      assert alert["title"] == String.duplicate("é", 79) <> "…"
      assert alert["subtitle"] == "Pip"
      assert alert["body"] =~ "Summary done"
      refute alert["body"] =~ "raw tool evidence"
      refute alert["body"] =~ ~r/[\p{Cc}\p{Cf}<>*`#]/u
      assert length(String.codepoints(alert["body"])) <= 160
      assert byte_size(body) < 4096
    end

    test "rechecks current membership, scopes, archive, and deletion before contacting providers" do
      for boundary <- [:removed, :revoked_scopes, :archived, :deleted] do
        owner = Atlas.OrbitFixtures.user_fixture(["accounts:read"])
        member = Atlas.OrbitFixtures.user_fixture(["accounts:read"])
        {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Sensitive title", "participant_ids" => [member.id]})
        thread = Repo.update!(Ecto.Changeset.change(thread, required_scopes: ["accounts:read"]))
        installation = register(member, ios_device())
        job_args = queued_orbit_args(installation, thread)

        case boundary do
          :removed ->
            :ok = Orbit.remove_participant(owner, thread, member.id)

          :revoked_scopes ->
            {:ok, _} = Roles.update_role(Roles.get_role_by_slug("test-#{member.id}"), %{scopes: []})

          :archived ->
            Repo.update!(Ecto.Changeset.change(thread, status: "archived"))

          :deleted ->
            Repo.delete!(thread)
        end

        assert {:cancel, :destination_unavailable} = perform_job(Deliver, job_args)
        assert Repo.reload!(installation).retired_at == nil
        refute_received {:request, _, _, _, _}
      end

      assert Repo.aggregate(from(a in Activity, where: a.action == "push_notification.delivery"), :count) == 4
    end

    test "rechecks access on provider retries", %{user: user, responses: responses} do
      {:ok, thread, _} = Orbit.ensure_private(user)
      installation = register(user, ios_device())
      job_args = queued_orbit_args(installation, thread)
      respond(responses, "api.push.apple.com", [{503, [], %{}}])

      assert {:error, :provider_unavailable} = perform_job(Deliver, job_args)
      assert_received {:request, "api.push.apple.com", _, _, _}
      Repo.update!(Ecto.Changeset.change(thread, status: "archived"))
      assert {:cancel, :destination_unavailable} = perform_job(Deliver, job_args)
      refute_received {:request, _, _, _, _}
    end

    test "only Orbit completion kinds require a readable thread", %{user: user} do
      installation = register(user, ios_device())
      nonexistent = Ecto.UUID.generate()

      assert :ok =
               perform_job(
                 Deliver,
                 args(installation, %{"kind" => "activity", "screen" => "orbit", "record_id" => nonexistent})
               )

      assert_received {:request, "api.push.apple.com", _, _, _}

      assert {:cancel, :destination_unavailable} =
               perform_job(
                 Deliver,
                 args(installation, %{"kind" => "orbit_completed", "screen" => "orbit", "record_id" => nonexistent})
               )

      for overrides <- [%{"screen" => "orbit", "record_id" => nil}, %{"screen" => "tasks"}] do
        assert {:cancel, :invalid_arguments} =
                 perform_job(Deliver, args(installation, Map.put(overrides, "kind", "orbit_completed")))
      end

      refute_received {:request, _, _, _, _}
      assert Repo.aggregate(Thread, :count) == 0
    end

    test "rejects missing, non-agent, cross-thread, and mismatched run sources", %{user: user} do
      {:ok, thread, _} = Orbit.ensure_private(user)
      {:ok, other} = Orbit.create_shared(user, %{"title" => "Another thread"})
      installation = register(user, ios_device())
      reply = orbit_reply(thread, user.id)
      other_reply = orbit_reply(other, user.id)
      job_args = queued_orbit_args(installation, thread, reply)

      for source_id <- [nil, "not-a-uuid", Ecto.UUID.generate(), other_reply.id] do
        assert {:cancel, :destination_unavailable} = perform_job(Deliver, Map.put(job_args, "message_id", source_id))
      end

      Repo.update!(Ecto.Changeset.change(reply, kind: "tool", tool_output: "Never push this evidence"))
      assert {:cancel, :destination_unavailable} = perform_job(Deliver, job_args)
      Repo.update!(Ecto.Changeset.change(Repo.reload!(reply), kind: "agent", run_id: other_reply.run_id))
      assert {:cancel, :destination_unavailable} = perform_job(Deliver, job_args)
      Repo.update!(Ecto.Changeset.change(Repo.reload!(reply), run_id: reply.run_id))
      run = Repo.get!(Run, reply.run_id)

      for status <- ~w(queued running failed cancelled interrupted) do
        Repo.update!(Ecto.Changeset.change(Repo.reload!(run), status: status))
        assert {:cancel, :destination_unavailable} = perform_job(Deliver, job_args)
      end

      Repo.update!(Ecto.Changeset.change(Repo.reload!(run), status: "succeeded", acting_user_id: user_fixture().id))
      assert {:cancel, :destination_unavailable} = perform_job(Deliver, job_args)
      refute_received {:request, _, _, _, _}
    end
  end

  defp queued_orbit_args(installation, thread, reply \\ nil) do
    reply = reply || orbit_reply(thread, installation.user_id)

    assert {:ok, _count} =
             Push.notify_user(installation.user_id, "orbit_completed", {"orbit", thread.id}, message_id: reply.id)

    jobs = all_enqueued(worker: Deliver)
    %{args: job_args} = Enum.find(jobs, &(&1.args["registration_id"] == installation.id))
    job_args
  end

  defp orbit_reply(thread, user_id, body \\ "The run is complete.") do
    {:ok, reply} =
      Repo.transaction(fn ->
        run =
          Repo.insert!(%Run{
            thread_id: thread.id,
            acting_user_id: user_id,
            status: "succeeded",
            trigger_seq: thread.last_seq
          })

        Orbit.append!(thread, %{kind: "agent", run_id: run.id, body: body, author_name: Orbit.agent_name()})
      end)

    reply
  end

  describe "send-time checks" do
    test "cancels without contacting providers once the app session's refresh grant is revoked", %{user: user} do
      installation = register(user, ios_device())

      Repo.update_all(from(t in Token, where: t.client_id == ^installation.oauth_client_id),
        set: [refresh_token_revoked_at: DateTime.utc_now()]
      )

      assert {:cancel, :registration_unavailable} = perform_job(Deliver, args(installation))
      assert Repo.reload!(installation).retired_reason == "session_ended"
      refute_received {:request, _, _, _, _}
    end

    test "cancels without contacting providers for expired, retired or reassigned registrations", %{user: user} do
      installation = register(user, ios_device())
      expired = DateTime.utc_now() |> DateTime.add(-1) |> DateTime.to_iso8601()

      assert {:cancel, :expired} = perform_job(Deliver, args(installation, %{"expires_at" => expired}))

      assert {:cancel, :registration_unavailable} =
               perform_job(Deliver, args(installation, %{"user_id" => user_fixture().id}))

      :ok = Push.unregister(user, installation.oauth_client_id, installation.installation_id)
      assert {:cancel, :registration_unavailable} = perform_job(Deliver, args(installation))
      refute_received {:request, _, _, _, _}
    end

    test "revalidates kind and destination from queued arguments", %{user: user} do
      installation = register(user, ios_device())

      for overrides <- [
            %{"kind" => "marketing"},
            %{"screen" => "settings", "record_id" => nil},
            %{"record_id" => "not-a-uuid"},
            %{"notification_id" => "nope"},
            %{"registration_id" => "nope"},
            %{"expires_at" => "tomorrow"}
          ] do
        assert {:cancel, reason} = perform_job(Deliver, args(installation, overrides))
        assert reason in [:invalid_arguments, :registration_unavailable]
      end

      refute_received {:request, _, _, _, _}
    end

    test "declares uniqueness per registration and notification", %{user: user} do
      installation = register(user, ios_device())
      job_args = args(installation)

      assert {:ok, %Oban.Job{conflict?: false}} = job_args |> Deliver.new() |> Oban.insert()
      assert {:ok, %Oban.Job{conflict?: true}} = job_args |> Deliver.new() |> Oban.insert()
    end

    test "audits terminal outcomes without tokens", %{user: user, responses: responses} do
      token = ios_token()
      installation = register(user, ios_device(%{"token" => token}))
      respond(responses, "api.push.apple.com", [{200, [], %{}}, {400, [], %{"reason" => "BadDeviceToken"}}])

      delivered = args(installation)
      assert :ok = perform_job(Deliver, delivered)
      assert {:cancel, :token_invalidated} = perform_job(Deliver, args(installation))

      outcomes =
        Repo.all(from a in Activity, where: a.action == "push_notification.delivery", order_by: a.id)

      assert [%{metadata: %{"outcome" => "delivered", "notification_id" => id, "kind" => "self_test"}}, invalidated] =
               outcomes

      assert id == delivered["notification_id"]
      assert invalidated.metadata["outcome"] == "cancelled"
      assert invalidated.metadata["reason"] == "token_invalidated"
      assert Enum.all?(outcomes, &(&1.interface == "worker" and &1.target_id == installation.id))
      refute inspect(Repo.all(Activity)) =~ token
    end

    test "jobs never contain the provider token", %{user: user} do
      token = ios_token()
      register(user, ios_device(%{"token" => token}))
      assert {:ok, 1} = Push.notify_user(user.id, "self_test", {"profile", nil})
      assert [%Oban.Job{args: job_args}] = all_enqueued(worker: Deliver)
      refute inspect(job_args) =~ token
      assert Repo.aggregate(Installation, :count) == 1
    end
  end
end
