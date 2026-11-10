defmodule Atlas.Orbit.SessionPrivacyTest do
  use Atlas.DataCase, async: true

  alias Atlas.Agents.Sessions
  alias Atlas.Agents.Sessions.Session
  alias Atlas.Orbit.Agent
  alias Atlas.Repo

  @sentinel "SECRET-SENTINEL private thread text"

  test "raised exceptions are stored as a category, never their message" do
    label = "orbit_run:#{Ecto.UUID.generate()}"

    assert_raise RuntimeError, fn ->
      Sessions.with_session(Agent, label, [], fn _opts -> raise @sentinel end)
    end

    assert_redacted(label, "exception:RuntimeError")
  end

  test "thrown and exited terms are stored as their kind" do
    label = "orbit_run:#{Ecto.UUID.generate()}"
    catch_exit(Sessions.with_session(Agent, label, [], fn _opts -> exit({:shutdown, @sentinel}) end))
    assert_redacted(label, "exit")
  end

  test "error reasons other than fixed categories are replaced" do
    label = "orbit_run:#{Ecto.UUID.generate()}"
    assert {:error, _} = Sessions.with_session(Agent, label, [], fn _opts -> {:error, %{body: @sentinel}} end)
    assert_redacted(label, "redacted")

    label = "orbit_run:#{Ecto.UUID.generate()}"

    assert {:error, "provider_billing"} =
             Sessions.with_session(Agent, label, [], fn _opts -> {:error, "provider_billing"} end)

    assert_redacted(label, "provider_billing")
  end

  test "prompts other than run labels and successful results are not stored" do
    assert {:ok, _} = Sessions.with_session(Agent, @sentinel, [], fn _opts -> {:ok, @sentinel} end)
    session = Repo.one!(from s in Session, where: s.agent == ^inspect(Agent) and s.prompt == "redacted")
    refute inspect(session) =~ "SECRET-SENTINEL"
    assert session.result == %{"redacted" => true}
  end

  defp assert_redacted(label, error) do
    session = Repo.one!(from s in Session, where: s.prompt == ^label)
    assert session.status == "failed"
    assert session.error == error
    refute inspect(session) =~ "SECRET-SENTINEL"
  end
end
