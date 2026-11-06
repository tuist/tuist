defmodule Tuist.Application.ReleaseEnvironmentTest do
  use ExUnit.Case, async: true

  for command <- ~w(start start_iex daemon daemon_iex) do
    test "#{command} requires a private cookie before enabling distribution" do
      {output, status} = environment(unquote(command), [{"RELEASE_COOKIE", nil}])
      assert status == 1
      assert output =~ "requires an explicit private RELEASE_COOKIE"
    end

    test "#{command} fixes the listener and preserves existing Erlang options" do
      {output, 0} = environment(unquote(command))
      assert output =~ "node=formation@127.0.0.1"
      assert output =~ "distribution=name"
      assert output =~ "options=-existing-option -kernel inet_dist_listen_min 9200 inet_dist_listen_max 9200"
    end
  end

  for port <- ["0", "65536", "invalid", "9100 -eval invalid", "999999999999999999999999999"] do
    test "rejects invalid distribution port #{inspect(port)}" do
      {output, status} = environment("start", [{"TUIST_CLUSTER_DISTRIBUTION_PORT", unquote(port)}])
      assert status == 1
      assert output =~ "must be an integer between 1 and 65535"
    end
  end

  for command <- ~w(remote rpc eval stop restart version) do
    test "#{command} does not take the server listener" do
      {output, 0} =
        environment(unquote(command), [
          {"RELEASE_COOKIE", nil},
          {"TUIST_CLUSTER_DISTRIBUTION_PORT", "invalid"}
        ])

      assert output =~ "options=-existing-option"
      refute output =~ "inet_dist_listen"
    end
  end

  test "a standalone server does not need a cluster cookie" do
    {output, 0} = environment("start", [{"TUIST_CLUSTER_DNS_SERVICE", nil}, {"RELEASE_COOKIE", nil}])
    assert output =~ "distribution=none"
    refute output =~ "inet_dist_listen"
  end

  test "explicit distribution cannot fall back to the public image cookie" do
    {output, status} =
      environment("start", [
        {"TUIST_CLUSTER_DNS_SERVICE", nil},
        {"RELEASE_DISTRIBUTION", "name"},
        {"RELEASE_COOKIE", nil}
      ])

    assert status == 1
    assert output =~ "requires an explicit private RELEASE_COOKIE"
  end

  test "an omitted listener uses the documented default" do
    {output, 0} = environment("start", [{"TUIST_CLUSTER_DISTRIBUTION_PORT", nil}])
    assert output =~ "inet_dist_listen_min 9100 inet_dist_listen_max 9100"
  end

  defp environment(command, overrides \\ []) do
    env = [
      {"RELEASE_COMMAND", command},
      {"RELEASE_DISTRIBUTION", nil},
      {"RELEASE_NODE", nil},
      {"RELEASE_COOKIE", "owned-test-cookie"},
      {"TUIST_CLUSTER_DNS_SERVICE", "formation.local"},
      {"TUIST_CLUSTER_APP_NAME", "formation"},
      {"TUIST_CLUSTER_DISTRIBUTION_PORT", "9200"},
      {"POD_IP", "127.0.0.1"},
      {"ELIXIR_ERL_OPTIONS", "-existing-option"}
    ]

    System.cmd(
      "sh",
      [
        "-c",
        ~s(. "$1"; printf 'node=%s\\ndistribution=%s\\noptions=%s\\n' "$RELEASE_NODE" "$RELEASE_DISTRIBUTION" "$ELIXIR_ERL_OPTIONS"),
        "release-environment-test",
        Path.expand("rel/env.sh.eex")
      ],
      env: Map.to_list(Map.merge(Map.new(env), Map.new(overrides))),
      stderr_to_stdout: true
    )
  end
end
