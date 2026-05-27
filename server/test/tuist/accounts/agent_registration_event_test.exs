defmodule Tuist.Accounts.AgentRegistrationEventTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Accounts.AgentRegistrationEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "create_changeset/1" do
    test "is valid with all attributes" do
      registration = agent_registration_fixture()
      user = AccountsFixtures.user_fixture()

      got =
        AgentRegistrationEvent.create_changeset(%{
          agent_registration_id: registration.id,
          event_type: :claimed,
          actor_ip: "127.0.0.1",
          claimed_by_user_id: user.id,
          metadata: %{"credential_type" => "access_token"},
          occurred_at: current_datetime()
        })

      assert got.valid?
      assert get_change(got, :event_type) == :claimed
      assert get_change(got, :metadata) == %{"credential_type" => "access_token"}
    end

    test "requires an agent registration, event type, and occurrence timestamp" do
      got = AgentRegistrationEvent.create_changeset(%{})

      assert "can't be blank" in errors_on(got).agent_registration_id
      assert "can't be blank" in errors_on(got).event_type
      assert "can't be blank" in errors_on(got).occurred_at
    end

    test "requires the agent registration to exist" do
      got =
        AgentRegistrationEvent.create_changeset(%{
          agent_registration_id: UUIDv7.generate(),
          event_type: :created,
          occurred_at: current_datetime()
        })

      assert {:error, got} = Repo.insert(got)
      assert "does not exist" in errors_on(got).agent_registration_id
    end

    test "requires the claimed user to exist when present" do
      registration = agent_registration_fixture()

      got =
        AgentRegistrationEvent.create_changeset(%{
          agent_registration_id: registration.id,
          event_type: :claimed,
          claimed_by_user_id: -1,
          occurred_at: current_datetime()
        })

      assert {:error, got} = Repo.insert(got)
      assert "does not exist" in errors_on(got).claimed_by_user_id
    end
  end

  defp agent_registration_fixture do
    attrs = %{
      registration_type: :email_verification,
      status: :pending,
      requested_credential_type: :access_token,
      email: "agent@example.com",
      claim_token_hash: "claim-token-hash",
      claim_view_token_hash: "claim-view-token-hash",
      otp_hash: "otp-hash",
      claim_token_expires_at: future_datetime(),
      otp_expires_at: future_datetime(),
      claim_attempt_id: "claim-attempt-id"
    }

    attrs
    |> AgentRegistration.create_email_verification_changeset()
    |> Repo.insert!()
  end

  defp current_datetime do
    DateTime.truncate(DateTime.utc_now(), :second)
  end

  defp future_datetime do
    DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.truncate(:second)
  end
end
