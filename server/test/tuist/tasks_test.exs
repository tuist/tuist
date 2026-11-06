defmodule Tuist.TasksTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Observability
  alias Tuist.Tasks

  setup :set_mimic_from_context

  defmodule Query do
    @moduledoc false
    def explode, do: raise("pool exhausted")
  end

  describe "parallel_tasks/2" do
    test "propagates only owned context and tracing, isolating siblings and the caller" do
      stub(Environment, :error_tracking_enabled?, fn -> true end)
      selected = %Account{id: 42, name: "tenant"}
      Observability.set_selection(%{selected_account: selected})
      Observability.feature_flag_evaluated(:runners, selected, true)
      Logger.metadata(request_id: "not inherited")
      Sentry.Context.set_request_context(%{headers: %{authorization: "not inherited"}})
      Sentry.Context.set_extra_context(%{arbitrary_request_value: "not inherited"})
      :otel_ctx.set_value(:private_request_value, "not inherited")
      :otel_tracer.set_current_span(:otel_tracer.from_remote_span(1234, 5678, 1))

      results =
        Tasks.parallel_tasks([
          fn ->
            event = Sentry.Event.create_event(exception: %RuntimeError{message: "task"})
            trace_id = :otel_span.trace_id(:otel_tracer.current_span_ctx())
            baggage = :otel_ctx.get_value(:private_request_value)
            private_metadata = Logger.metadata()[:request_id]
            Observability.set_selection(%{selected_account: %Account{id: 43, name: "other"}})
            {event, trace_id, baggage, private_metadata, Logger.metadata()[:selected_account_id]}
          end,
          fn -> Sentry.Context.get_all() end
        ])

      [{event, 1234, :undefined, nil, 43}, sibling] = results
      assert event.tags.selected_account_id == 42
      assert event.tags["feature_flag.runners"] == "true"
      refute Map.has_key?(event.extra, :arbitrary_request_value)
      refute inspect(event.request) =~ "not inherited"
      assert sibling.tags.selected_account_id == 42
      assert sibling.tags["feature_flag.runners"] == "true"
      assert Logger.metadata()[:selected_account_id] == 42
      assert Sentry.Context.get_all().tags.selected_account_id == 42
      assert Sentry.Context.get_all().extra.arbitrary_request_value == "not inherited"
      assert :otel_ctx.get_value(:private_request_value) == "not inherited"
    end

    test "returns the results in the order the functions were given" do
      assert [1, 2, 3] = Tasks.parallel_tasks([fn -> 1 end, fn -> 2 end, fn -> 3 end])
    end

    test "reraises a task's exception with the task's stacktrace when the caller traps exits" do
      Process.flag(:trap_exit, true)

      {exception, stacktrace} =
        try do
          Tasks.parallel_tasks([fn -> :ok end, &Query.explode/0])
        rescue
          exception -> {exception, __STACKTRACE__}
        end

      assert %RuntimeError{message: "pool exhausted"} = exception
      assert Enum.any?(stacktrace, &match?({Query, :explode, 0, _}, &1))
    end

    test "reraises as soon as a task fails instead of waiting for its siblings" do
      Process.flag(:trap_exit, true)
      parent = self()

      gate =
        spawn_link(fn ->
          receive do
            {:sibling, sibling} -> send(parent, {:sibling, sibling})
          end

          receive do
            {:await_sibling, failing} -> send(failing, :sibling_started)
          end
        end)

      queries = [
        fn ->
          send(gate, {:await_sibling, self()})

          receive do
            :sibling_started -> raise "pool exhausted"
          end
        end,
        fn ->
          send(gate, {:sibling, self()})
          Process.sleep(:infinity)
        end
      ]

      assert_raise RuntimeError, "pool exhausted", fn -> Tasks.parallel_tasks(queries) end

      assert_receive {:sibling, sibling}
      ref = Process.monitor(sibling)
      assert_receive {:DOWN, ^ref, :process, ^sibling, _reason}
    end

    test "exits with the reason when a task exits without an exception" do
      Process.flag(:trap_exit, true)

      assert catch_exit(Tasks.parallel_tasks([fn -> exit(:boom) end])) == :boom
    end
  end

  test "the synchronous run_async path restores context after an exception" do
    stub(Environment, :error_tracking_enabled?, fn -> true end)
    Observability.set_selection(%{selected_account: %Account{id: 42, name: "caller"}})

    for sentry <- [nil, [tags: %{caller_tag: "preserved"}]] do
      Logger.metadata(sentry: sentry)

      assert_raise RuntimeError, "failure", fn ->
        Tasks.run_async(fn ->
          Observability.set_selection(%{selected_account: %Account{id: 43, name: "task"}})
          raise "failure"
        end)
      end

      assert Logger.metadata()[:selected_account_id] == 42
      assert Sentry.Context.get_all().tags.selected_account_id == 42
      assert Logger.metadata()[:sentry] == sentry

      assert {:ok, _pid} = Tasks.run_async(fn -> :ok end)
      assert Logger.metadata()[:sentry] == sentry
    end
  end
end
