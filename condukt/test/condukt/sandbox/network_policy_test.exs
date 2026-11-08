defmodule Condukt.Sandbox.NetworkPolicyTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox.NetworkPolicy
  alias Condukt.Sandbox.NetworkPolicy.Request

  defp request(host) do
    %Request{
      id: "r-#{System.unique_integer([:positive])}",
      host: host,
      port: 443,
      started_at: DateTime.utc_now()
    }
  end

  describe "new/1" do
    test "accepts a keyword list" do
      policy = NetworkPolicy.new(rules: [allow: ["a.com"]], default: :allow)
      assert %NetworkPolicy{default: :allow, rules: [{:allow, ["a.com"]}]} = policy
    end

    test "passes through an existing struct unchanged" do
      policy = %NetworkPolicy{rules: [deny: ["x"]]}
      assert NetworkPolicy.new(policy) == policy
    end

    test "treats nil as the deny-everything default" do
      assert %NetworkPolicy{rules: [], default: :deny} = NetworkPolicy.new(nil)
    end
  end

  describe "evaluate/2 with the keyword rule walker" do
    test "an allow-list rule allows matching hosts and falls through otherwise" do
      policy = %NetworkPolicy{
        rules: [allow: ["api.github.com"]],
        default: :deny
      }

      assert :allow = NetworkPolicy.evaluate(policy, request("api.github.com"))
      assert {:deny, :default_deny} = NetworkPolicy.evaluate(policy, request("evil.com"))
    end

    test "a deny-list rule denies matching hosts" do
      policy = %NetworkPolicy{
        rules: [deny: ["*.internal"], allow: ["**"]],
        default: :deny
      }

      assert {:deny, :matched_deny_list} =
               NetworkPolicy.evaluate(policy, request("svc.internal"))

      assert :allow = NetworkPolicy.evaluate(policy, request("api.github.com"))
    end

    test "rules are evaluated top to bottom" do
      policy = %NetworkPolicy{
        rules: [deny: ["api.github.com"], allow: ["api.github.com"]],
        default: :deny
      }

      assert {:deny, :matched_deny_list} =
               NetworkPolicy.evaluate(policy, request("api.github.com"))
    end

    test "a decide rule (function) delegates to the callable" do
      decider = fn _ctx, req ->
        if req.host == "ok.test", do: :allow, else: {:deny, :nope}
      end

      policy = %NetworkPolicy{rules: [decide: decider]}

      assert :allow = NetworkPolicy.evaluate(policy, request("ok.test"))
      assert {:deny, :nope} = NetworkPolicy.evaluate(policy, request("bad.test"))
    end

    test "the default action fires when no rule matches" do
      assert :allow =
               NetworkPolicy.evaluate(
                 %NetworkPolicy{default: :allow},
                 request("anything.test")
               )

      assert {:deny, :default_deny} =
               NetworkPolicy.evaluate(
                 %NetworkPolicy{default: :deny},
                 request("anything.test")
               )
    end
  end

  describe "deliver/4 telemetry" do
    test "emits a telemetry event with bytes measurements and request metadata" do
      test_pid = self()
      handler_id = "net-test-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:condukt, :sandbox, :network_policy, :request_closed],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      req = %{request("x.com") | bytes_in: 100, bytes_out: 50}

      :ok = NetworkPolicy.deliver(nil, :request_closed, req)

      assert_receive {:telemetry, %{bytes_in: 100, bytes_out: 50}, %{request: ^req}}
    end

    test "passes :reason through metadata" do
      test_pid = self()
      handler_id = "net-test-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:condukt, :sandbox, :network_policy, :request_denied],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok =
        NetworkPolicy.deliver(nil, :request_denied, request("evil.com"), reason: :no_allow_match)

      assert_receive {:telemetry, %{reason: :no_allow_match}}
    end
  end
end
