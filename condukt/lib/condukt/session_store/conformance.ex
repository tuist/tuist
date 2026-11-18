defmodule Condukt.SessionStore.Conformance do
  @moduledoc """
  Tests every `Condukt.SessionStore` has to pass, for use in a store's own
  test suite.

      defmodule MyApp.RedisStoreTest do
        use ExUnit.Case, async: true
        use Condukt.SessionStore.Conformance, store: MyApp.RedisStore

        setup do
          prefix = "test:\#{System.unique_integer([:positive])}"

          %{
            store_opts: [redix: MyApp.Redix, key: prefix <> ":a"],
            other_store_opts: [redix: MyApp.Redix, key: prefix <> ":b"]
          }
        end
      end

  The test module provides a `setup` that returns `:store_opts` and
  `:other_store_opts`: options for two distinct, empty sessions in the store,
  which the tests use to check that one session's state never shows up in
  the other's.

  Pass `journal: false` for a store that only implements the snapshot
  callbacks. A store that implements the journal callbacks should pass the
  journal tests, since `Condukt.Session` relies on what they check to resume
  an interrupted run.
  """

  defmacro __using__(opts) do
    store = Keyword.fetch!(opts, :store)
    journal? = Keyword.get(opts, :journal, true)

    quote do
      alias Condukt.Message
      alias Condukt.SessionStore.Snapshot

      describe "#{inspect(unquote(store))} conformance: snapshots" do
        test "a missing snapshot is not found", %{store_opts: opts} do
          assert unquote(store).load(opts) == :not_found
        end

        test "returns the saved snapshot unchanged", %{store_opts: opts} do
          snapshot = Snapshot.new(%{id: "s", messages: [Message.user("hi")], model: "m"})

          assert :ok = unquote(store).save(snapshot, opts)
          assert unquote(store).load(opts) == {:ok, snapshot}
        end

        # The session's record of its runs is not a struct field, so a store
        # that writes snapshots field by field can drop it without noticing.
        test "keeps the session's record of its runs", %{store_opts: opts} do
          requests = [{"r2", {:error, :aborted}}, {"r1", {:ok, "done"}}]
          snapshot = %{messages: [Message.user("hi")]} |> Snapshot.new() |> Snapshot.put_runs(3, requests)

          assert :ok = unquote(store).save(snapshot, opts)
          assert {:ok, loaded} = unquote(store).load(opts)
          assert Snapshot.runs(loaded) == {3, requests}
        end

        test "a save replaces the previous snapshot", %{store_opts: opts} do
          first = Snapshot.new(%{messages: [Message.user("first")]})
          second = Snapshot.new(%{messages: [Message.user("second")]})

          assert :ok = unquote(store).save(first, opts)
          assert :ok = unquote(store).save(second, opts)
          assert unquote(store).load(opts) == {:ok, second}
        end

        test "clearing removes the snapshot and tolerates a missing one", %{store_opts: opts} do
          assert :ok = unquote(store).clear(opts)
          assert :ok = unquote(store).save(Snapshot.new(%{}), opts)
          assert :ok = unquote(store).clear(opts)
          assert unquote(store).load(opts) == :not_found
        end

        test "sessions do not share snapshots", %{store_opts: opts, other_store_opts: other} do
          assert :ok = unquote(store).save(Snapshot.new(%{messages: [Message.user("a")]}), opts)
          assert unquote(store).load(other) == :not_found
        end
      end

      if unquote(journal?) do
        describe "#{inspect(unquote(store))} conformance: journal" do
          test "declares the journal callbacks" do
            assert Condukt.SessionStore.journal?(unquote(store))
          end

          test "an empty journal loads as no records", %{store_opts: opts} do
            assert unquote(store).load_journal(opts) == {:ok, []}
          end

          test "returns records unchanged and in append order across appends", %{store_opts: opts} do
            prompt = Message.user("go")
            assistant = Message.assistant([{:text, "x"}, {:tool_call, "c1", "Read", %{"path" => "a"}}])
            result = Message.tool_result("c1", {:error, "boom"})

            assert :ok = unquote(store).append_journal([{:run_start, 1, %{message: prompt}}], opts)

            assert :ok =
                     unquote(store).append_journal(
                       [{:assistant, 1, assistant}, {:tool_intent, 1, %{call_id: "c1", replay_safe: false}}],
                       opts
                     )

            assert :ok = unquote(store).append_journal([{:tool_result, 2, result}], opts)

            assert unquote(store).load_journal(opts) ==
                     {:ok,
                      [
                        {:run_start, 1, %{message: prompt}},
                        {:assistant, 1, assistant},
                        {:tool_intent, 1, %{call_id: "c1", replay_safe: false}},
                        {:tool_result, 2, result}
                      ]}
          end

          test "clearing the journal leaves the snapshot", %{store_opts: opts} do
            snapshot = Snapshot.new(%{messages: [Message.user("kept")]})
            assert :ok = unquote(store).save(snapshot, opts)
            assert :ok = unquote(store).append_journal([{:resume, 1, nil}], opts)

            assert :ok = unquote(store).clear_journal(opts)
            assert unquote(store).load_journal(opts) == {:ok, []}
            assert unquote(store).load(opts) == {:ok, snapshot}
            assert :ok = unquote(store).clear_journal(opts)
          end

          test "saving or clearing the snapshot leaves the journal", %{store_opts: opts} do
            assert :ok = unquote(store).append_journal([{:resume, 1, nil}], opts)
            assert :ok = unquote(store).save(Snapshot.new(%{}), opts)
            assert :ok = unquote(store).clear(opts)
            assert unquote(store).load_journal(opts) == {:ok, [{:resume, 1, nil}]}
          end

          test "sessions do not share journals", %{store_opts: opts, other_store_opts: other} do
            assert :ok = unquote(store).append_journal([{:resume, 1, nil}], opts)
            assert unquote(store).load_journal(other) == {:ok, []}
          end
        end
      end
    end
  end
end
