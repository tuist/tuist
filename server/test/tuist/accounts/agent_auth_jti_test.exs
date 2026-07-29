defmodule Tuist.Accounts.AgentAuthJTITest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts.AgentAuthJTI

  describe "create_changeset/1" do
    test "is valid with all attributes" do
      got = AgentAuthJTI.create_changeset(valid_attrs())

      assert got.valid?
      assert get_change(got, :issuer) == "https://agent.example.com"
      assert get_change(got, :jti) == "jti-123"
    end

    test "requires an issuer" do
      got = AgentAuthJTI.create_changeset(Map.delete(valid_attrs(), :issuer))

      assert "can't be blank" in errors_on(got).issuer
    end

    test "requires a jti" do
      got = AgentAuthJTI.create_changeset(Map.delete(valid_attrs(), :jti))

      assert "can't be blank" in errors_on(got).jti
    end

    test "requires an expiration timestamp" do
      got = AgentAuthJTI.create_changeset(Map.delete(valid_attrs(), :expires_at))

      assert "can't be blank" in errors_on(got).expires_at
    end

    test "requires the issuer and jti pair to be unique" do
      Repo.insert!(AgentAuthJTI.create_changeset(valid_attrs()))

      assert {:error, got} = Repo.insert(AgentAuthJTI.create_changeset(valid_attrs()))
      assert "has already been taken" in errors_on(got).issuer
    end

    test "allows the same jti for different issuers" do
      Repo.insert!(AgentAuthJTI.create_changeset(valid_attrs()))

      got =
        valid_attrs()
        |> Map.put(:issuer, "https://another-agent.example.com")
        |> AgentAuthJTI.create_changeset()

      assert {:ok, %AgentAuthJTI{}} = Repo.insert(got)
    end
  end

  defp valid_attrs do
    %{
      issuer: "https://agent.example.com",
      jti: "jti-123",
      expires_at: DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.truncate(:second)
    }
  end
end
