defmodule Mix.Tasks.Tuist.TestEnumerationTest do
  # Runs `mix tuist.test --cover` on a project of its own, since requiring
  # test files is refused while a suite, this one, is running.
  use ExUnit.Case, async: true

  @moduletag timeout: 300_000

  @mix_exs """
  defmodule Fixture.MixProject do
    use Mix.Project

    def project do
      [
        app: :fixture,
        version: "0.1.0",
        deps: [{:tuist_ex, path: TUIST_EX, only: :test}],
        aliases: [test: "tuist.test"],
        test_coverage: [summary: [threshold: 0]]
      ]
    end
  end
  """

  @files %{
    "lib/fixture.ex" => """
    defmodule Fixture do
      def add(a, b), do: a + b
    end
    """,
    "test/test_helper.exs" => "ExUnit.start(exclude: [:integration])\n",
    "test/cart_test.exs" => """
    defmodule CartTest do
      use ExUnit.Case

      @tag :focus
      test "adds", do: assert(Fixture.add(1, 1) == 2)

      describe "checkout/1" do
        test "charges", do: assert(true)
      end
    end
    """,
    "test/order_test.exs" => """
    defmodule OrderTest do
      use ExUnit.Case
      test "ships" do
        unused = 1
        assert true
      end

      @tag :integration
      test "calls the carrier", do: flunk("never runs by default")
    end
    """
  }

  # The project's configuration leaves the integration test out of every run,
  # as a test plan disables a test.
  @suite [
    %{"module" => "CartTest", "suite" => "", "name" => "adds", "enabled" => true},
    %{"module" => "CartTest", "suite" => "checkout/1", "name" => "charges", "enabled" => true},
    %{"module" => "OrderTest", "suite" => "", "name" => "calls the carrier", "enabled" => false},
    %{"module" => "OrderTest", "suite" => "", "name" => "ships", "enabled" => true}
  ]

  # Outside any Git checkout, so the run reads no history from this one.
  setup do
    dir =
      Path.join(System.tmp_dir!(), "tuist-ex-enumeration-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    File.write!(
      Path.join(dir, "mix.exs"),
      String.replace(@mix_exs, "TUIST_EX", inspect(File.cwd!()))
    )

    for {file, content} <- @files do
      File.mkdir_p!(Path.dirname(Path.join(dir, file)))
      File.write!(Path.join(dir, file), content)
    end

    {:ok, socket} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, port} = :inet.port(socket)
    owner = self()
    # The plan of a shard that runs CartTest, without an uploaded build.
    responses = %{
      "/api/projects/acme/fixture/tests/shards/plan/0" =>
        ~s({"modules":["CartTest"],"shard_plan_id":"0191e5d0-0000-7000-8000-000000000000"})
    }

    spawn_link(fn -> accept(socket, owner, responses) end)

    %{dir: dir, url: "http://127.0.0.1:#{port}"}
  end

  test "lists every test of the suite, whatever the run picked", %{dir: dir, url: url} do
    # A full run lists the tests it ran.
    run = tuist_test(dir, url, [])
    assert names(run["test_modules"]) == ["adds", "charges", "ships"]
    assert sorted(run["enumerated_tests"]) == @suite

    # --only reports what it left out as excluded.
    run = tuist_test(dir, url, ["--only", "focus"])
    assert names(run["test_modules"]) == ["adds"]
    assert sorted(run["enumerated_tests"]) == @suite

    # An explicit file leaves the other one unloaded: it is read after the
    # run, without showing the warnings of a file that did not run.
    {run, output} = tuist_test_with_output(dir, url, ["test/cart_test.exs"])
    refute output =~ ~s(variable "unused" is unused)
    assert names(run["test_modules"]) == ["adds", "charges"]
    assert sorted(run["enumerated_tests"]) == @suite

    # So does --stale, once its manifest says only one file changed.
    tuist_test(dir, url, ["--stale"])
    # Ahead of the manifest, which has a resolution of a second.
    File.touch!(Path.join(dir, "test/order_test.exs"), System.os_time(:second) + 5)
    run = tuist_test(dir, url, ["--stale"])
    assert names(run["test_modules"]) == ["ships"]
    assert sorted(run["enumerated_tests"]) == @suite
  end

  test "a shard lists only its share, even when its arguments pick files", %{dir: dir, url: url} do
    run =
      tuist_test(dir, url, [
        "--shard-index",
        "0",
        "--shard-reference",
        "plan",
        "test/cart_test.exs:5"
      ])

    assert names(run["test_modules"]) == ["adds"]
    assert sorted(run["enumerated_tests"]) == Enum.filter(@suite, &(&1["module"] == "CartTest"))
  end

  test "lists nothing without --cover", %{dir: dir, url: url} do
    run = tuist_test(dir, url, [], [])
    refute Map.has_key?(run, "enumerated_tests")
  end

  defp tuist_test(dir, url, args, cover \\ ["--cover"]) do
    {run, _output} = tuist_test_with_output(dir, url, args, cover)
    run
  end

  defp tuist_test_with_output(dir, url, args, cover \\ ["--cover"]) do
    {output, status} =
      System.cmd(
        System.find_executable("mix"),
        ["tuist.test", "--url", url, "--project", "acme/fixture"] ++ cover ++ args,
        cd: dir,
        env:
          [{"MIX_ENV", "test"}, {"TUIST_TOKEN", "token"}, {"TUIST_DEBUG", "1"}] ++
            Enum.map(
              ~w(MIX_BUILD_PATH MIX_DEPS_PATH MIX_EXS MIX_TEST_PARTITION TUIST_URL TUIST_PROJECT),
              &{&1, nil}
            ),
        stderr_to_stdout: true
      )

    assert status == 0, output
    # A file the run loaded is not required again.
    refute output =~ "redefining module", output
    assert_receive {:request, "/api/projects/acme/fixture/tests", body}, 5_000, output
    {JSON.decode!(body), output}
  end

  defp names(modules),
    do: modules |> Enum.flat_map(& &1["test_cases"]) |> Enum.map(& &1["name"]) |> Enum.sort()

  defp sorted(tests), do: Enum.sort_by(tests, &{&1["module"], &1["name"]})

  # Answers every request, with an empty object unless told otherwise, and
  # hands the test each one.
  defp accept(socket, owner, responses) do
    {:ok, client} = :gen_tcp.accept(socket)
    {path, body} = read_request(client)
    send(owner, {:request, path, body})
    response = Map.get(responses, path, "{}")

    :gen_tcp.send(
      client,
      "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(response)}\r\nconnection: close\r\n\r\n" <>
        response
    )

    :gen_tcp.close(client)
    accept(socket, owner, responses)
  end

  defp read_request(client, buffer \\ "") do
    case :binary.split(buffer, "\r\n\r\n") do
      [head, body] ->
        [request_line | headers] = String.split(head, "\r\n")
        [_method, path, _version] = String.split(request_line, " ")

        length =
          Enum.find_value(headers, 0, fn header ->
            case String.split(header, ":", parts: 2) do
              [name, value] ->
                if String.downcase(name) == "content-length",
                  do: String.to_integer(String.trim(value))

              _ ->
                nil
            end
          end)

        {path, read_body(client, body, length)}

      [_incomplete] ->
        {:ok, data} = :gen_tcp.recv(client, 0)
        read_request(client, buffer <> data)
    end
  end

  defp read_body(_client, body, length) when byte_size(body) >= length, do: body

  defp read_body(client, body, length) do
    {:ok, data} = :gen_tcp.recv(client, 0)
    read_body(client, body <> data, length)
  end
end
