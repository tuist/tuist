alias Tuist.Marketing.Stats

Process.flag(:trap_exit, true)
Logger.configure(level: :warning)
Application.ensure_all_started(:inets)
Code.require_file("controller.exs", __DIR__)
start = &ScaleEndToEndController.start/2

wait = fn predicate ->
  Enum.reduce_while(1..200, false, fn _, _ ->
    if predicate.(),
      do: {:halt, true},
      else:
        (
          Process.sleep(50)
          {:cont, false}
        )
  end) || raise "Timed out waiting for server state"
end

check = fn condition, message ->
  if !condition, do: raise(message)
  IO.puts("PASS: #{message}")
end

request = fn method, path, headers, body ->
  url = String.to_charlist("http://127.0.0.1:14100" <> path)
  headers = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
  req = if method == :post, do: {url, headers, ~c"application/json", JSON.encode!(body)}, else: {url, headers}

  {:ok, {{_, status, _}, response_headers, response_body}} =
    :httpc.request(method, req, [timeout: 15_000], body_format: :binary)

  {status, Map.new(response_headers, fn {k, v} -> {List.to_string(k), List.to_string(v)} end), response_body}
end

mcp = fn token, method, params ->
  headers = [
    {"authorization", "Bearer #{token}"},
    {"mcp-protocol-version", "2026-07-28"},
    {"mcp-method", method},
    {"mcp-session-id", "stale-session-from-another-node"}
  ]

  headers = if method == "tools/call", do: headers ++ [{"mcp-name", params["name"]}], else: headers

  params =
    Map.put(params, "_meta", %{
      "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities" => %{}
    })

  {status, headers, body} =
    request.(:post, "/mcp", headers, %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params})

  {status, headers, JSON.decode!(body)}
end

screenshot = fn name ->
  path = "/tmp/tuist-scale-e2e/#{name}.png"
  File.rm(path)
  executable = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

  args = [
    "--headless",
    "--no-sandbox",
    "--disable-gpu",
    "--no-first-run",
    "--disable-background-networking",
    "--disable-extensions",
    "--user-data-dir=/tmp/tuist-scale-e2e/chrome-#{name}",
    "--window-size=1280,1000",
    "--screenshot=#{path}",
    "http://127.0.0.1:14100/.well-known/mcp/server-card.json"
  ]

  browser = Port.open({:spawn_executable, executable}, [:binary, :exit_status, :stderr_to_stdout, args: args])
  {:os_pid, pid} = Port.info(browser, :os_pid)

  try do
    wait.(fn -> File.exists?(path) and File.stat!(path).size > 10_000 end)
  after
    System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
    if Port.info(browser), do: Port.close(browser)
  end
end

{a, na} = start.("127.0.0.1", 14_101)
{b, nb} = start.(System.fetch_env!("TUIST_E2E_SECOND_ADDRESS"), 14_102)
Process.put(:servers, [a, b])

try do
  wait.(fn -> :erpc.call(a, Node, :list, []) == [nb] and :erpc.call(b, Node, :list, []) == [na] end)
  check.(true, "two complete servers discovered each other through actual address records")

  for peer <- [a, b] do
    check.(
      :erpc.call(peer, Application, :get_env, [:kernel, :inet_dist_listen_min]) == 19_110 and
        :erpc.call(peer, Application, :get_env, [:kernel, :inet_dist_listen_max]) == 19_110,
      "server distribution listener uses the fixed port"
    )
  end

  {_id, token, handle} = :erpc.call(a, ScaleEndToEnd, :seed, [])

  responses =
    for _ <- 1..12 do
      {200, headers, response} = mcp.(token, "tools/call", %{"name" => "list_accounts", "arguments" => %{}})

      response["result"]["structuredContent"]["accounts"]
      |> Enum.any?(&(&1["handle"] == handle))
      |> check.("authenticated tool returns the shared account")

      true = response["result"]["resultType"] == "complete"
      false = Map.has_key?(headers, "mcp-session-id")
      headers["x-verification-backend"]
    end

  check.(
    Enum.frequencies(responses) == %{"1" => 6, "2" => 6},
    "round-robin HTTP tool calls reached both servers without initialization or sessions"
  )

  for method <- ["server/discover", "tools/list"] do
    {200, _, first} = mcp.(token, method, %{})
    {200, _, second} = mcp.(token, method, %{})
    check.(first == second, "#{method} gives the same response on either server")
  end

  {revoked_id, revoked_token, _} = :erpc.call(a, ScaleEndToEnd, :seed, [])
  for _ <- 1..2, do: {200, _, _} = mcp.(revoked_token, "tools/list", %{})
  :ok = :erpc.call(a, ScaleEndToEnd, :revoke, [revoked_id])
  for _ <- 1..2, do: {401, _, _} = mcp.(revoked_token, "tools/list", %{})
  check.(true, "credentials warmed on both servers are rejected on both immediately after revocation")

  {member_id, member_token, organization_id, account_handle, project_handle} =
    :erpc.call(a, ScaleEndToEnd, :permission_subject, [])

  project_params = %{
    "name" => "get_project",
    "arguments" => %{"account_handle" => account_handle, "project_handle" => project_handle}
  }

  for _ <- 1..2 do
    {200, _, response} = mcp.(member_token, "tools/call", project_params)
    false = response["result"]["isError"] == true
  end

  :ok = :erpc.call(a, ScaleEndToEnd, :revoke_membership, [member_id, organization_id])

  for _ <- 1..2 do
    {200, _, response} = mcp.(member_token, "tools/call", project_params)
    true = response["result"]["isError"]
  end

  check.(true, "project access warmed on both servers is denied on both after membership removal")
  for peer <- [a, b], do: :erpc.call(peer, Tuist.KeyValueStore, :put, ["e2e-balance", :stale])
  :ok = :erpc.call(a, Tuist.KeyValueStore, :invalidate, ["e2e-balance"])
  wait.(fn -> :erpc.call(b, Tuist.KeyValueStore, :get, ["e2e-balance"]) == nil end)
  check.(true, "a mutation on one full server invalidates the other server's cached value")
  :erpc.call(a, FunWithFlags, :disable, [:scale_e2e_shared_flag])
  false = :erpc.call(b, FunWithFlags, :enabled?, [:scale_e2e_shared_flag])
  {:ok, true} = :erpc.call(a, FunWithFlags, :enable, [:scale_e2e_shared_flag])
  wait.(fn -> :erpc.call(b, FunWithFlags, :enabled?, [:scale_e2e_shared_flag]) end)
  {:ok, false} = :erpc.call(a, FunWithFlags, :disable, [:scale_e2e_shared_flag])
  wait.(fn -> !:erpc.call(b, FunWithFlags, :enabled?, [:scale_e2e_shared_flag]) end)
  check.(true, "feature-flag changes invalidate the other server's warmed flag cache")
  {partition_user_id, partition_token, _} = :erpc.call(a, ScaleEndToEnd, :seed, [])
  for _ <- 1..2, do: {200, _, _} = mcp.(partition_token, "tools/list", %{})
  :erpc.call(a, Node, :set_cookie, [nb, :e2e_partition_cookie])
  :erpc.call(a, Node, :disconnect, [nb])
  wait.(fn -> :erpc.call(a, Node, :list, []) == [] and :erpc.call(b, Node, :list, []) == [] end)
  for _ <- 1..4, do: {200, _, _} = mcp.(token, "tools/call", %{"name" => "list_accounts", "arguments" => %{}})
  :ok = :erpc.call(a, ScaleEndToEnd, :revoke, [partition_user_id])
  for _ <- 1..2, do: {401, _, _} = mcp.(partition_token, "tools/list", %{})
  check.(true, "disconnected servers keep serving stateless tools and immediately reject revoked credentials")
  :erpc.call(a, Node, :set_cookie, [nb, Node.get_cookie()])
  wait.(fn -> :erpc.call(a, Node, :list, []) == [nb] and :erpc.call(b, Node, :list, []) == [na] end)
  check.(true, "servers rediscover each other when the simulated distribution partition heals")

  case :erpc.call(a, ExAws, :request, [ExAws.S3.put_bucket("scale-e2e", "us-east-1")]) do
    {:ok, _} -> :ok
    {:error, {:http_error, 409, _}} -> :ok
    error -> raise "Object-storage setup failed: #{inspect(error)}"
  end

  title = "Two server verification #{System.system_time(:millisecond)}"
  path = :erpc.call(a, TuistWeb.Helpers.OpenGraph, :image_path, [:marketing_text, [title: title]])
  observer_a = :erpc.call(a, ScaleEndToEndObserver, :start, [])
  observer_b = :erpc.call(b, ScaleEndToEndObserver, :start, [])

  images =
    1..8 |> Enum.map(fn _ -> Task.async(fn -> request.(:get, path, [], nil) end) end) |> Enum.map(&Task.await(&1, 30_000))

  check.(
    Enum.all?(images, fn {status, _, body} -> status == 200 and byte_size(body) > 10_000 end),
    "concurrent signed image requests succeed through both servers and real object storage"
  )

  check.(
    images |> Enum.map(fn {_, _, body} -> :crypto.hash(:sha256, body) end) |> Enum.uniq() |> length() == 1,
    "both servers return identical image bytes"
  )

  Process.sleep(100)

  render_count =
    :erpc.call(a, ScaleEndToEndObserver, :count, [observer_a, title]) +
      :erpc.call(b, ScaleEndToEndObserver, :count, [observer_b, title])

  check.(render_count == 1, "eight concurrent image requests render once across the two servers")
  screenshot.("e2e-both")
  leader = :erpc.call(a, :global, :whereis_name, [{Stats, :poller}])

  check.(
    is_pid(leader) and leader == :erpc.call(b, :global, :whereis_name, [{Stats, :poller}]),
    "both servers agree on one marketing poller"
  )

  {departing, survivor, survivor_node, host, port} =
    if node(leader) == na,
      do: {a, b, nb, "127.0.0.1", 14_101},
      else: {b, a, na, System.fetch_env!("TUIST_E2E_SECOND_ADDRESS"), 14_102}

  :erpc.call(survivor, Tuist.KeyValueStore, :put, ["e2e-missed", :stale])

  traffic =
    Task.async(fn ->
      loop = fn loop, results ->
        receive do
          :stop -> Enum.reverse(results)
        after
          25 -> loop.(loop, [request.(:get, "/ready", [], nil) | results])
        end
      end

      loop.(loop, [])
    end)

  task_marker = "/tmp/tuist-scale-e2e/drained-task"
  File.rm(task_marker)
  {:ok, _} = :erpc.call(departing, ScaleEndToEnd, :pending_task, [task_marker])
  ScaleEndToEndController.stop(departing)
  check.(File.read(task_marker) == {:ok, "completed"}, "graceful shutdown finishes an already-running supervised task")
  Process.put(:servers, [survivor])

  wait.(fn ->
    :erpc.call(survivor, Node, :list, []) == [] and :erpc.call(survivor, Tuist.KeyValueStore, :get, ["e2e-missed"]) == nil
  end)

  check.(true, "node departure clears the survivor's potentially stale cache")
  for _ <- 1..4, do: {200, _, _} = mcp.(token, "tools/call", %{"name" => "list_accounts", "arguments" => %{}})
  check.(true, "authenticated tool calls continue while one complete server is down")
  screenshot.("e2e-survivor")

  wait.(fn ->
    case :erpc.call(survivor, :global, :whereis_name, [{Stats, :poller}]) do
      pid when is_pid(pid) -> node(pid) == survivor_node
      _ -> false
    end
  end)

  check.(true, "the surviving server elects its marketing poller after leader departure")
  {restarted, restarted_node} = start.(host, port)
  Process.put(:servers, [survivor, restarted])

  wait.(fn ->
    :erpc.call(survivor, Node, :list, []) == [restarted_node] and
      :erpc.call(restarted, Node, :list, []) == [survivor_node]
  end)

  check.(true, "a restarted full server automatically rejoins through address discovery")
  send(traffic.pid, :stop)
  statuses = traffic |> Task.await(30_000) |> Enum.map(fn {status, _, _} -> status end)

  check.(
    Enum.all?(statuses, &(&1 == 200)),
    "all #{length(statuses)} readiness requests succeed during departure, failover, and restart"
  )

  backends =
    for _ <- 1..8 do
      {200, headers, response} = mcp.(token, "tools/call", %{"name" => "list_accounts", "arguments" => %{}})
      false = response["result"]["isError"] == true
      headers["x-verification-backend"]
    end

  check.(
    MapSet.new(backends) == MapSet.new(["1", "2"]),
    "the same credential works on both servers after restart without initialization"
  )

  if System.get_env("TUIST_REDIS_URL") do
    {_id, rate_token, _handle} = :erpc.call(survivor, ScaleEndToEnd, :seed, [])
    remaining = 60_000 - rem(System.system_time(:millisecond), 60_000)
    if remaining < 10_000, do: Process.sleep(remaining + 20)

    limited =
      for _ <- 1..130 do
        {status, _, _} = mcp.(rate_token, "tools/list", %{})
        status
      end

    check.(
      Enum.frequencies(limited) == %{200 => 120, 429 => 10},
      "both HTTP servers enforce one shared 120-request budget"
    )

    {_id, outage_token, _handle} = :erpc.call(survivor, ScaleEndToEnd, :seed, [])
    redis_cli = System.fetch_env!("TUIST_E2E_REDIS_CLI")
    {_, 0} = System.cmd(redis_cli, ["-p", "14105", "CLIENT", "PAUSE", "3000", "ALL"])
    for _ <- 1..2, do: {429, _, _} = mcp.(outage_token, "tools/list", %{})
    check.(true, "both HTTP servers deny admission during a shared-store timeout")
    {_, 0} = System.cmd(redis_cli, ["-p", "14105", "PING"])
    for _ <- 1..2, do: {200, _, _} = mcp.(outage_token, "tools/list", %{})
    check.(true, "HTTP admission recovers after the shared store responds again")
  end

  screenshot.("e2e-rejoined")
  IO.puts("All full-server end-to-end checks passed")
after
  for peer <- Process.get(:servers, []), do: if(Node.ping(peer) == :pong, do: ScaleEndToEndController.stop(peer))
end
