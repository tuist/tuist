defmodule Condukt.Sandbox.NetworkPolicy.DeciderTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox.NetworkPolicy
  alias Condukt.Sandbox.NetworkPolicy.Context
  alias Condukt.Sandbox.NetworkPolicy.Decider
  alias Condukt.Sandbox.NetworkPolicy.Request

  defp request(host \\ "evil.com") do
    %Request{id: "r1", host: host, port: 443, started_at: DateTime.utc_now()}
  end

  defp context(session_id \\ "s1") do
    %Context{session_id: session_id, recent_messages: [], request: request(), metadata: %{}}
  end

  defp policy_with(decider, extra \\ []) do
    tuning =
      []
      |> maybe_put(:timeout, Keyword.get(extra, :decide_timeout))
      |> maybe_put(:cache, Keyword.get(extra, :decision_cache))

    decide_value = if tuning == [], do: decider, else: [{:call, decider} | tuning]

    %NetworkPolicy{
      rules: [decide: decide_value],
      default: Keyword.get(extra, :default, :deny)
    }
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: kw ++ [{key, value}]

  describe "decide/4 with function decider" do
    test "allow" do
      policy = policy_with(fn _, _ -> :allow end)
      assert {:allow, %{}} = Decider.decide(policy, context(), request(), %{})
    end

    test "deny passes reason through" do
      policy = policy_with(fn _, _ -> {:deny, :nope} end)
      assert {{:deny, :nope}, _} = Decider.decide(policy, context(), request(), %{})
    end

    test "context and request are passed to the decider" do
      test_pid = self()

      policy =
        policy_with(fn ctx, req ->
          send(test_pid, {:invoked, ctx, req})
          :allow
        end)

      Decider.decide(policy, context("s99"), request("api.example.com"), %{})

      assert_receive {:invoked, %Context{session_id: "s99"}, %Request{host: "api.example.com"}}
    end
  end

  describe "decide/4 with {Mod, fun} tuple" do
    defmodule Allower do
      def allow_all(_ctx, _req), do: :allow
      def deny_all(_ctx, _req), do: {:deny, :nope_mf}
    end

    test "calls the named function" do
      policy = policy_with({Allower, :allow_all})
      assert {:allow, _} = Decider.decide(policy, context(), request(), %{})

      policy = policy_with({Allower, :deny_all})
      assert {{:deny, :nope_mf}, _} = Decider.decide(policy, context(), request(), %{})
    end
  end

  describe "decide/4 with behaviour-backed decider" do
    defmodule BehaviourDecider do
      @behaviour Condukt.Sandbox.NetworkPolicy.Decider

      @impl true
      def decide(_ctx, _req, opts) do
        Keyword.fetch!(opts, :result)
      end
    end

    test "calls module.decide/3 with opts when given {module, opts}" do
      policy = policy_with({BehaviourDecider, result: :allow})
      assert {:allow, _} = Decider.decide(policy, context(), request(), %{})

      policy = policy_with({BehaviourDecider, result: {:deny, :foo}})
      assert {{:deny, :foo}, _} = Decider.decide(policy, context(), request(), %{})
    end

    test "calls module.decide/3 with [] when the module is given alone" do
      defmodule NoOpts do
        @behaviour Condukt.Sandbox.NetworkPolicy.Decider

        @impl true
        def decide(_ctx, _req, []), do: :allow
      end

      policy = policy_with(NoOpts)
      assert {:allow, _} = Decider.decide(policy, context(), request(), %{})
    end
  end

  describe "decide/4 timeout" do
    test "denies with :decider_timeout when the decider exceeds the limit" do
      policy =
        policy_with(
          fn _, _ ->
            Process.sleep(200)
            :allow
          end,
          decide_timeout: 50,
          default: :deny
        )

      assert {{:deny, :decider_timeout}, _} = Decider.decide(policy, context(), request(), %{})
    end
  end

  describe "decide/4 cache" do
    test "second call for the same host reuses the cached decision" do
      counter = :counters.new(1, [])

      policy =
        policy_with(fn _, _ ->
          :counters.add(counter, 1, 1)
          :allow
        end)

      {decision, cache} = Decider.decide(policy, context(), request(), %{})
      assert decision == :allow
      assert :counters.get(counter, 1) == 1

      {decision, _cache} = Decider.decide(policy, context(), request(), cache)
      assert decision == :allow
      assert :counters.get(counter, 1) == 1
    end

    test "cache: false invokes the decider every time" do
      counter = :counters.new(1, [])

      policy =
        policy_with(
          fn _, _ ->
            :counters.add(counter, 1, 1)
            :allow
          end,
          decision_cache: false
        )

      Decider.decide(policy, context(), request(), %{})
      Decider.decide(policy, context(), request(), %{})

      assert :counters.get(counter, 1) == 2
    end
  end

  describe "decide/4 error handling" do
    test "crashing decider denies with :decider_error" do
      policy = policy_with(fn _, _ -> raise "boom" end)
      assert {{:deny, :decider_error}, _} = Decider.decide(policy, context(), request(), %{})
    end

    test "non-decision return denies with :decider_bad_return" do
      policy = policy_with(fn _, _ -> :not_a_decision end)
      assert {{:deny, :decider_bad_return}, _} = Decider.decide(policy, context(), request(), %{})
    end
  end

  describe "decide/4 with no decide rule" do
    test "returns the default action immediately" do
      policy = %NetworkPolicy{rules: [], default: :allow}
      assert {:allow, _} = Decider.decide(policy, context(), request(), %{})

      policy = %NetworkPolicy{rules: [], default: :deny}
      assert {{:deny, :default_deny}, _} = Decider.decide(policy, context(), request(), %{})
    end
  end

  describe "spec/1" do
    test "a bare callable takes the defaults" do
      fun = fn _, _ -> :allow end

      assert %{
               call: ^fun,
               timeout: 5_000,
               cache: true,
               context_messages: 5,
               context_metadata: %{}
             } = Decider.spec(fun)
    end

    test "{module, opts} is treated as a bare callable, not the configured form" do
      assert %{call: {Allower, [a: 1]}, timeout: 5_000} = Decider.spec({Allower, a: 1})
    end

    test "the configured keyword form overrides the knobs" do
      fun = fn _, _ -> :allow end

      assert %{
               call: ^fun,
               timeout: 50,
               cache: false,
               context_messages: 12,
               context_metadata: %{tenant: "acme"}
             } =
               Decider.spec(
                 call: fun,
                 timeout: 50,
                 cache: false,
                 context_messages: 12,
                 context_metadata: %{tenant: "acme"}
               )
    end

    test "the configured form requires :call" do
      assert_raise ArgumentError, ~r/requires a :call entry/, fn ->
        Decider.spec(timeout: 50)
      end
    end
  end

  describe "policy_spec/1" do
    test "returns the first decide rule's spec" do
      fun = fn _, _ -> :allow end
      policy = %NetworkPolicy{rules: [allow: ["a.com"], decide: [call: fun, timeout: 99]]}
      assert %{call: ^fun, timeout: 99} = Decider.policy_spec(policy)
    end

    test "returns nil when there is no decide rule" do
      assert Decider.policy_spec(%NetworkPolicy{rules: [allow: ["a.com"]]}) == nil
    end
  end
end
