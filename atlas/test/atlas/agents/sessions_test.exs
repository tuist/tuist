defmodule Atlas.Agents.SessionsTest do
  use Atlas.DataCase, async: true

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Agents.Sessions
  alias Atlas.Agents.Sessions.Session
  alias Atlas.TestSupport.Agents.NoopAgent
  alias Condukt.SessionID

  # The agent runtime emits its telemetry from a task the sandbox has not granted
  # a connection to, so every run through it logs the session events the handler
  # drops. That warning now carries a stacktrace, which is worth having in
  # production and only noise here.
  @moduletag :capture_log

  describe "run/3" do
    test "runs Atlas Condukt modules as one-shot sessions" do
      assert {:ok, "handled: draft note"} = Sessions.run(NoopAgent, "draft note")

      assert %Session{agent: "Atlas.TestSupport.Agents.NoopAgent", status: "succeeded"} =
               Repo.one!(Session)
    end

    test "records sanitized session exits from the agent runtime as failed sessions" do
      assert {:error, {:session_exit, {:noproc, {GenServer, :call, [__MODULE__.MissingAgent, :redacted, 1]}}}} =
               Sessions.run(__MODULE__.MissingAgent, "test prompt", timeout: 1)

      assert %Session{
               status: "failed",
               error: error
             } =
               Session
               |> order_by(desc: :started_at)
               |> Repo.one!()

      assert error =~ ":session_exit"
      assert error =~ ":noproc"
      assert error =~ ":redacted"
      refute error =~ "test prompt"
    end
  end

  describe "with_session/4" do
    test "records caller-owned streaming sessions" do
      account = insert_account!()

      assert {:ok, "streamed response"} =
               Sessions.with_session(NoopAgent, "thread prompt", [account_id: account.id], fn opts ->
                 assert is_binary(opts[:id])
                 {:ok, "streamed response"}
               end)

      assert %Session{
               agent: "Atlas.TestSupport.Agents.NoopAgent",
               account_id: account_id,
               prompt: "thread prompt",
               result: %{"text" => "streamed response"},
               status: "succeeded"
             } = Repo.one!(Session)

      assert account_id == account.id
    end
  end

  describe "list_sessions/1" do
    test "returns sessions newest first with pagination meta" do
      older = insert_running_session!(started_at: ~U[2026-05-01 10:00:00.000000Z])
      newer = insert_running_session!(started_at: ~U[2026-05-08 10:00:00.000000Z])

      {sessions, meta} = Sessions.list_sessions(page: 1, page_size: 10)

      assert Enum.map(sessions, & &1.id) == [newer.id, older.id]
      assert meta.total_count == 2
      assert meta.total_pages == 1
      assert meta.current_page == 1
      assert meta.page_size == 10
    end

    test "paginates results with page and page_size" do
      sessions =
        for i <- 1..3 do
          insert_running_session!(started_at: DateTime.add(~U[2026-05-01 00:00:00.000000Z], i, :hour))
        end

      [oldest, middle, newest] = sessions

      {page_one, meta_one} = Sessions.list_sessions(page: 1, page_size: 2)
      {page_two, meta_two} = Sessions.list_sessions(page: 2, page_size: 2)

      assert Enum.map(page_one, & &1.id) == [newest.id, middle.id]
      assert Enum.map(page_two, & &1.id) == [oldest.id]

      assert meta_one.total_count == 3
      assert meta_one.total_pages == 2
      assert meta_one.current_page == 1
      assert meta_two.current_page == 2
    end

    test "returns zero pages when no sessions exist" do
      {sessions, meta} = Sessions.list_sessions(page: 1, page_size: 5)

      assert sessions == []
      assert meta.total_count == 0
      assert meta.total_pages == 0
    end
  end

  describe "attach_account/2" do
    test "links a running session to an account" do
      account = insert_account!()
      session = insert_running_session!()

      assert :ok = Sessions.attach_account(session.id, account.id)

      assert %{account_id: account_id} = Repo.get!(Session, session.id)
      assert account_id == account.id
    end

    test "is a no-op when the session already has an account" do
      account_a = insert_account!()
      account_b = insert_account!()
      session = insert_running_session!(account_id: account_a.id)

      assert :ok = Sessions.attach_account(session.id, account_b.id)

      assert %{account_id: account_id} = Repo.get!(Session, session.id)
      assert account_id == account_a.id
    end

    test "is a no-op for an unknown session id" do
      assert :ok = Sessions.attach_account(SessionID.generate(), Ecto.UUID.generate())
    end

    test "ignores invalid account ids" do
      session = insert_running_session!()

      assert :ok = Sessions.attach_account(session.id, "not-a-uuid")

      assert %{account_id: nil} = Repo.get!(Session, session.id)
    end
  end

  defp insert_account!(attrs \\ %{}) do
    defaults = %{
      account_key: "sessions-test:#{System.unique_integer([:positive])}",
      name: "Sessions Test",
      segment: :lead
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_running_session!(attrs \\ []) do
    %{
      id: SessionID.generate(),
      agent: "Atlas.Agents.SessionsTest",
      prompt: "test prompt",
      status: "running",
      started_at: DateTime.utc_now(),
      account_id: Keyword.get(attrs, :account_id)
    }
    |> Session.create_changeset()
    |> Repo.insert!()
  end
end
