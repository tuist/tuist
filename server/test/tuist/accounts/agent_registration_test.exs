defmodule Tuist.Accounts.AgentRegistrationTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts.AgentRegistration
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "create_email_verification_changeset/1" do
    test "is valid with all attributes" do
      got = AgentRegistration.create_email_verification_changeset(email_verification_attrs())

      assert got.valid?
      assert get_change(got, :email) == "agent@example.com"
      assert get_change(got, :registration_type) == :email_verification
      assert get_change(got, :requested_credential_type) == :access_token
    end

    test "normalizes the email" do
      got =
        email_verification_attrs()
        |> Map.put(:email, "  Agent@Example.COM  ")
        |> AgentRegistration.create_email_verification_changeset()

      assert get_change(got, :email) == "agent@example.com"
    end

    test "requires email verification fields" do
      got = AgentRegistration.create_email_verification_changeset(%{})

      assert "can't be blank" in errors_on(got).registration_type
      assert "can't be blank" in errors_on(got).status
      assert "can't be blank" in errors_on(got).requested_credential_type
      assert "can't be blank" in errors_on(got).email
      assert "can't be blank" in errors_on(got).claim_token_hash
      assert "can't be blank" in errors_on(got).claim_view_token_hash
      assert "can't be blank" in errors_on(got).otp_hash
      assert "can't be blank" in errors_on(got).claim_token_expires_at
      assert "can't be blank" in errors_on(got).otp_expires_at
      assert "can't be blank" in errors_on(got).claim_attempt_id
    end

    test "requires the claim token hash to be unique" do
      Repo.insert!(AgentRegistration.create_email_verification_changeset(email_verification_attrs()))

      attrs =
        email_verification_attrs()
        |> Map.put(:claim_view_token_hash, "another-view-token")
        |> Map.put(:email, "another@example.com")

      assert {:error, got} = Repo.insert(AgentRegistration.create_email_verification_changeset(attrs))
      assert "has already been taken" in errors_on(got).claim_token_hash
    end

    test "requires the claim view token hash to be unique" do
      Repo.insert!(AgentRegistration.create_email_verification_changeset(email_verification_attrs()))

      attrs =
        email_verification_attrs()
        |> Map.put(:claim_token_hash, "another-claim-token")
        |> Map.put(:email, "another@example.com")

      assert {:error, got} = Repo.insert(AgentRegistration.create_email_verification_changeset(attrs))
      assert "has already been taken" in errors_on(got).claim_view_token_hash
    end
  end

  describe "create_anonymous_changeset/1" do
    test "is valid with all attributes" do
      account_token = AccountsFixtures.account_token_fixture()

      got =
        [account_token_id: account_token.id]
        |> anonymous_attrs()
        |> AgentRegistration.create_anonymous_changeset()

      assert got.valid?
      assert get_change(got, :registration_type) == :anonymous
      assert get_change(got, :requested_credential_type) == :api_key
    end

    test "requires anonymous registration fields" do
      got = AgentRegistration.create_anonymous_changeset(%{})

      assert "can't be blank" in errors_on(got).registration_type
      assert "can't be blank" in errors_on(got).status
      assert "can't be blank" in errors_on(got).requested_credential_type
      assert "can't be blank" in errors_on(got).email
      assert "can't be blank" in errors_on(got).claim_token_hash
      assert "can't be blank" in errors_on(got).claim_token_expires_at
      assert "can't be blank" in errors_on(got).account_token_id
    end
  end

  describe "create_agent_provider_changeset/1" do
    test "is valid with all required attributes" do
      user = AccountsFixtures.user_fixture()

      got =
        [claimed_by_user_id: user.id]
        |> agent_provider_attrs()
        |> AgentRegistration.create_agent_provider_changeset()

      assert got.valid?
      assert get_change(got, :email) == "agent@example.com"
      assert get_change(got, :registration_type) == :agent_provider
    end

    test "normalizes the email" do
      user = AccountsFixtures.user_fixture()

      got =
        [claimed_by_user_id: user.id]
        |> agent_provider_attrs()
        |> Map.put(:email, "  Agent@Example.COM  ")
        |> AgentRegistration.create_agent_provider_changeset()

      assert get_change(got, :email) == "agent@example.com"
    end

    test "requires agent provider registration fields" do
      got = AgentRegistration.create_agent_provider_changeset(%{})

      assert "can't be blank" in errors_on(got).registration_type
      assert "can't be blank" in errors_on(got).status
      assert "can't be blank" in errors_on(got).requested_credential_type
      assert "can't be blank" in errors_on(got).email
      assert "can't be blank" in errors_on(got).claim_token_hash
      assert "can't be blank" in errors_on(got).claim_token_expires_at
      assert "can't be blank" in errors_on(got).claimed_at
      assert "can't be blank" in errors_on(got).claimed_by_user_id
      assert "can't be blank" in errors_on(got).issuer
      assert "can't be blank" in errors_on(got).subject
      assert "can't be blank" in errors_on(got).audience
      assert "can't be blank" in errors_on(got).client_id
      assert "can't be blank" in errors_on(got).assertion_jti
    end
  end

  describe "refresh_claim_changeset/2" do
    test "updates claim fields and resets the attempt count" do
      registration = %AgentRegistration{otp_attempt_count: 3}

      got =
        AgentRegistration.refresh_claim_changeset(registration, %{
          claim_view_token_hash: "claim-view-token-hash",
          otp_hash: "otp-hash",
          otp_expires_at: future_datetime(),
          claim_attempt_id: "attempt-id",
          otp_attempt_count: 0,
          claim_requested_ip: "127.0.0.1",
          email: "agent@example.com"
        })

      assert got.valid?
      assert get_change(got, :otp_attempt_count) == 0
      assert get_change(got, :claim_requested_ip) == "127.0.0.1"
    end

    test "requires refreshed claim fields" do
      got = AgentRegistration.refresh_claim_changeset(%AgentRegistration{}, %{})

      assert "can't be blank" in errors_on(got).claim_view_token_hash
      assert "can't be blank" in errors_on(got).otp_hash
      assert "can't be blank" in errors_on(got).otp_expires_at
      assert "can't be blank" in errors_on(got).claim_attempt_id
    end
  end

  describe "increment_otp_attempts_changeset/1" do
    test "increments the otp attempt count" do
      got = AgentRegistration.increment_otp_attempts_changeset(%AgentRegistration{otp_attempt_count: 2})

      assert get_change(got, :otp_attempt_count) == 3
    end
  end

  describe "claim_changeset/2" do
    test "is valid with claim attributes" do
      user = AccountsFixtures.user_fixture()

      got =
        AgentRegistration.claim_changeset(%AgentRegistration{}, %{
          status: :claimed,
          claimed_at: current_datetime(),
          claimed_by_user_id: user.id,
          claim_completed_ip: "127.0.0.1",
          credential_jti: "credential-jti"
        })

      assert got.valid?
      assert get_change(got, :status) == :claimed
    end

    test "requires claim fields" do
      got = AgentRegistration.claim_changeset(%AgentRegistration{}, %{})

      assert "can't be blank" in errors_on(got).status
      assert "can't be blank" in errors_on(got).claimed_at
      assert "can't be blank" in errors_on(got).claimed_by_user_id
    end
  end

  describe "expire_changeset/1" do
    test "marks the registration as expired" do
      got = AgentRegistration.expire_changeset(%AgentRegistration{status: :pending})

      assert get_change(got, :status) == :expired
    end
  end

  describe "revoke_changeset/2" do
    test "is valid with revoke attributes" do
      got =
        AgentRegistration.revoke_changeset(%AgentRegistration{}, %{
          status: :revoked,
          revoked_at: current_datetime()
        })

      assert got.valid?
      assert get_change(got, :status) == :revoked
    end

    test "requires revoke fields" do
      got = AgentRegistration.revoke_changeset(%AgentRegistration{}, %{})

      assert "can't be blank" in errors_on(got).status
      assert "can't be blank" in errors_on(got).revoked_at
    end
  end

  defp email_verification_attrs do
    %{
      registration_type: :email_verification,
      status: :pending,
      requested_credential_type: :access_token,
      email: "agent@example.com",
      claim_token_hash: "claim-token-hash",
      claim_view_token_hash: "claim-view-token-hash",
      otp_hash: "otp-hash",
      claim_token_expires_at: future_datetime(),
      otp_expires_at: future_datetime(),
      claim_attempt_id: "claim-attempt-id",
      registration_ip: "127.0.0.1",
      claim_requested_ip: "127.0.0.1"
    }
  end

  defp anonymous_attrs(overrides) do
    Map.merge(
      %{
        registration_type: :anonymous,
        status: :pending,
        requested_credential_type: :api_key,
        email: "anonymous-agent@example.com",
        claim_token_hash: "anonymous-claim-token-hash",
        claim_token_expires_at: future_datetime(),
        registration_ip: "127.0.0.1"
      },
      Map.new(overrides)
    )
  end

  defp agent_provider_attrs(overrides) do
    Map.merge(
      %{
        registration_type: :agent_provider,
        status: :claimed,
        requested_credential_type: :access_token,
        email: "agent@example.com",
        claim_token_hash: "agent-provider-claim-token-hash",
        claim_token_expires_at: future_datetime(),
        claimed_at: current_datetime(),
        issuer: "https://agent.example.com",
        subject: "agent-subject",
        audience: "https://tuist.dev",
        client_id: "agent-client",
        assertion_jti: "assertion-jti"
      },
      Map.new(overrides)
    )
  end

  defp current_datetime do
    DateTime.truncate(DateTime.utc_now(), :second)
  end

  defp future_datetime do
    DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.truncate(:second)
  end
end
