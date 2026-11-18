defmodule Condukt.Sessions.Inbox.Conformance do
  @moduledoc """
  The tests every `Condukt.Sessions.Inbox` must pass, whatever it stores
  inputs in.

  Use it in a test module of the inbox:

      defmodule MyApp.SessionInboxTest do
        use ExUnit.Case, async: true
        use Condukt.Sessions.Inbox.Conformance, inbox: {MyApp.SessionInbox, []}
      end

  The `:inbox` option is the inbox the tests use. A `setup` that returns
  `:inbox` overrides it, for example to start one inbox per test. Each test
  uses session ids of its own, so tests may share an inbox and run
  concurrently. One test takes and puts from several processes at once, so
  run the suite where processes the test starts reach the inbox's storage.
  """

  alias __MODULE__, as: Conformance
  alias Condukt.SessionID
  alias Condukt.Sessions.Inbox
  alias Condukt.Sessions.Input

  # Aliases in the quoted tests resolve here, not in the test module.
  defmacro __using__(opts) do
    quote do
      describe "Condukt.Sessions.Inbox conformance" do
        setup context do
          inbox = Map.get(context, :inbox) || unquote(Keyword.get(opts, :inbox))
          if is_nil(inbox), do: raise(ArgumentError, "pass :inbox to use, or return it from setup")
          %{inbox: inbox}
        end

        test "takes the inputs in the order they were put, with every field", %{inbox: inbox} do
          id = Conformance.session_id()
          sender = Conformance.session_id()

          first =
            Conformance.input(id, "first", "r1", from: sender, notify: "key-1", report: true)

          second = Conformance.input(id, "second", "r2")

          assert Inbox.put(inbox, first) == :ok
          assert Inbox.put(inbox, second) == :ok
          assert {:ok, [taken_first, taken_second]} = Inbox.take(inbox, id)

          assert Conformance.same?(taken_first, first)
          assert Conformance.same?(taken_second, second)
          assert Inbox.take(inbox, id) == {:ok, []}
        end

        test "accepts a request id once per session, also after its input was taken", %{inbox: inbox} do
          id = Conformance.session_id()
          other = Conformance.session_id()
          input = &Conformance.input/3

          assert Inbox.put(inbox, input.(id, "first", "r1")) == :ok
          assert Inbox.put(inbox, input.(id, "retry", "r1")) == {:error, :duplicate}
          assert {:ok, [%{text: "first"}]} = Inbox.take(inbox, id)

          assert Inbox.put(inbox, input.(id, "late retry", "r1")) == {:error, :duplicate}
          assert Inbox.take(inbox, id) == {:ok, []}

          # Request ids are scoped to their session.
          assert Inbox.put(inbox, input.(other, "first", "r1")) == :ok
        end

        test "takes only the session's own inputs", %{inbox: inbox} do
          id = Conformance.session_id()
          other = Conformance.session_id()
          input = &Conformance.input/3

          assert Inbox.take(inbox, id) == {:ok, []}
          assert Inbox.put(inbox, input.(id, "mine", "r1")) == :ok
          assert Inbox.put(inbox, input.(other, "theirs", "r1")) == :ok

          assert {:ok, [%{text: "mine"}]} = Inbox.take(inbox, id)
          assert {:ok, [%{text: "theirs"}]} = Inbox.take(inbox, other)
        end

        test "gives each input to one of several concurrent takers, in order", %{inbox: inbox} do
          id = Conformance.session_id()
          request_ids = for n <- 1..40, do: "r" <> String.pad_leading(Integer.to_string(n), 2, "0")

          # The takers keep taking while the inputs arrive, until told to stop.
          takers = for _taker <- 1..4, do: Task.async(fn -> Conformance.take_until_stopped(inbox, id, []) end)

          for request_id <- request_ids do
            :ok = Inbox.put(inbox, Conformance.input(id, "x", request_id))
            Process.sleep(1)
          end

          Enum.each(takers, &send(&1.pid, :stop))
          {:ok, rest} = Inbox.take(inbox, id)
          batches = [rest | Enum.flat_map(takers, &Task.await/1)]

          taken = for batch <- batches, input <- batch, do: input.request_id
          assert Enum.sort(taken) == request_ids

          for batch <- batches do
            batch_ids = Enum.map(batch, & &1.request_id)
            assert batch_ids == Enum.sort(batch_ids)
          end
        end
      end
    end
  end

  @doc false
  def session_id, do: SessionID.generate()

  @doc false
  def input(session_id, text, request_id, opts \\ []) do
    {:ok, input} = Input.new(session_id, text, [request_id: request_id] ++ opts)
    input
  end

  @doc false
  # Every field as it was put; the timestamp to the second, since a store may
  # keep less precision.
  def same?(taken, put) do
    Map.delete(taken, :submitted_at) == Map.delete(put, :submitted_at) and
      match?(%DateTime{}, taken.submitted_at) and
      abs(DateTime.diff(taken.submitted_at, put.submitted_at, :millisecond)) < 1_000
  end

  @doc false
  # Takes until told to stop, returning each non-empty batch. The pause keeps
  # the takers from spinning while the inputs arrive.
  def take_until_stopped(inbox, id, batches) do
    {:ok, batch} = Inbox.take(inbox, id)
    batches = if batch == [], do: batches, else: [batch | batches]

    receive do
      :stop -> batches
    after
      1 -> take_until_stopped(inbox, id, batches)
    end
  end
end
