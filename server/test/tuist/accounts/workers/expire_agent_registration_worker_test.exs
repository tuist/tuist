defmodule Tuist.Accounts.Workers.ExpireAgentRegistrationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Accounts.AgentRegistrationEvent
  alias Tuist.Accounts.Workers.ExpireAgentRegistrationWorker
  alias Tuist.Repo

  test "expires an unclaimed registration and records the transition" do
    registration =
      %{
        registration_type: :email_verification,
        status: :pending,
        requested_credential_type: :access_token,
        email: "agent@example.com",
        claim_token_hash: :crypto.hash(:sha256, "claim-token"),
        claim_view_token_hash: :crypto.hash(:sha256, "claim-view-token"),
        otp_hash: :crypto.hash(:sha256, "123456"),
        claim_token_expires_at: DateTime.add(DateTime.utc_now(), -1, :second),
        otp_expires_at: DateTime.add(DateTime.utc_now(), -1, :second),
        claim_attempt_id: "claim-attempt-id"
      }
      |> AgentRegistration.create_email_verification_changeset()
      |> Repo.insert!()

    assert :ok = perform_job(ExpireAgentRegistrationWorker, %{registration_id: registration.id})
    assert Repo.get!(AgentRegistration, registration.id).status == :expired

    assert Repo.exists?(
             from(e in AgentRegistrationEvent,
               where: e.agent_registration_id == ^registration.id and e.event_type == :expired
             )
           )
  end

  test "leaves claimed registrations unchanged" do
    user = TuistTestSupport.Fixtures.AccountsFixtures.user_fixture()

    registration =
      %{
        registration_type: :email_verification,
        status: :pending,
        requested_credential_type: :access_token,
        email: user.email,
        claim_token_hash: :crypto.hash(:sha256, "claimed-token"),
        claim_view_token_hash: :crypto.hash(:sha256, "claimed-view-token"),
        otp_hash: :crypto.hash(:sha256, "654321"),
        claim_token_expires_at: DateTime.add(DateTime.utc_now(), -1, :second),
        otp_expires_at: DateTime.add(DateTime.utc_now(), -1, :second),
        claim_attempt_id: "claimed-attempt-id"
      }
      |> AgentRegistration.create_email_verification_changeset()
      |> Repo.insert!()
      |> AgentRegistration.claim_changeset(%{
        status: :claimed,
        claimed_at: DateTime.utc_now(),
        claimed_by_user_id: user.id
      })
      |> Repo.update!()

    assert :ok = perform_job(ExpireAgentRegistrationWorker, %{registration_id: registration.id})
    assert Repo.get!(AgentRegistration, registration.id).status == :claimed
  end
end
