# Manual end-to-end smoke test for the Kura rollout pipeline against
# a local kind cluster. Not part of the automated suite.
#
# Setup:
#
#   kind create cluster --name kura-dev --kubeconfig /tmp/kura-kind.kubeconfig
#
# Run (from the `server/` directory; --no-start so the dev Phoenix
# endpoint doesn't fight with `mise run dev` for port 8080):
#
#   TUIST_KURA_KUBECONFIG_PATH_LOCAL_1=/tmp/kura-kind.kubeconfig \
#   MIX_ENV=dev mix run --no-start test/manual/kura_local_smoke.exs
#
# The script:
#   1. Spins up a fresh user/account (named kura-e2e-<timestamp>).
#   2. Records a Kura version row.
#   3. Inserts a deployment for (account, local, that version).
#   4. Confirms the Oban job sits in the DB.
#   5. Runs `Tuist.Kura.Workers.RolloutWorker.perform/1` inline so you
#      see the helm/kubectl output go through the worker, the namespace
#      get created, helm install run, and the StatefulSet come up in
#      kind.
#   6. Prints the final deployment status and the captured ClickHouse
#      log lines.
#
# Tear down:
#
#   kind delete cluster --name kura-dev
#
# Notes:
#   - The script intentionally avoids starting the application
#     supervision tree so it can run alongside `mise run dev`. It boots
#     only the apps it needs (Repo, IngestRepo, Oban, Briefly, Req,
#     Tzdata).
#   - Use Kura >= 0.3.0 (which contains the PR #10446 warm-rollout
#     primitives, including the `/ready` endpoint the chart's
#     readinessProbe relies on). Older images return 404 on `/ready`.

Application.put_env(:tuist, :clickhouse_writes_async, false)

{:ok, _} = Application.ensure_all_started(:logger)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:ch)
{:ok, _} = Application.ensure_all_started(:oban)
{:ok, _} = Application.ensure_all_started(:briefly)
{:ok, _} = Application.ensure_all_started(:req)
{:ok, _} = Application.ensure_all_started(:tzdata)
{:ok, _} = Application.ensure_all_started(:phoenix_pubsub)

{:ok, _repo} = Tuist.Repo.start_link()
{:ok, _ingest} = Tuist.IngestRepo.start_link()
{:ok, _pubsub} = Phoenix.PubSub.Supervisor.start_link(name: Tuist.PubSub)

{:ok, _oban} =
  Oban.start_link(
    repo: Tuist.Repo,
    queues: false,
    plugins: false,
    notifier: Oban.Notifiers.PG
  )

alias Tuist.Accounts
alias Tuist.Kura
alias Tuist.Kura.KuraDeployment
alias Tuist.Kura.KuraServer
alias Tuist.Kura.Workers.RolloutWorker
alias Tuist.Repo

handle = "kura-e2e-#{:os.system_time(:second)}"
email = "#{handle}@example.com"

password =
  "ClimbingMountFuji!" <> Base.encode16(:crypto.strong_rand_bytes(8))

{:ok, user} = Accounts.create_user(email, password: password)
account = Accounts.get_account_from_user(user)
IO.puts("→ account #{account.name} (id=#{account.id})")

{:ok, _} =
  Kura.record_version(
    "0.3.0",
    DateTime.utc_now() |> DateTime.truncate(:second)
  )

IO.puts("→ recorded version 0.1.0")

{:ok, %KuraServer{} = server} =
  Kura.create_server(%{
    account_id: account.id,
    region: "local",
    spec: :small,
    image_tag: "0.3.0",
    requested_by_user_id: user.id
  })

deployment = List.first(server.deployments)

IO.puts(
  "→ server #{server.id} status=#{server.status} spec=#{server.spec} volume=#{server.volume_size_gi}Gi"
)

IO.puts(
  "→ initial deployment #{deployment.id} oban_job_id=#{deployment.oban_job_id}"
)

%{rows: [[count]]} =
  Repo.query!(
    "SELECT count(*) FROM oban_jobs WHERE id = $1",
    [deployment.oban_job_id]
  )

IO.puts("→ #{count} Oban job(s) in DB for this deployment")

IO.puts(
  "→ running RolloutWorker inline (this shells out to helm/rollout.sh against kind)"
)

result = RolloutWorker.perform(%Oban.Job{args: %{"deployment_id" => deployment.id}})
IO.puts("→ worker returned: #{inspect(result)}")

final = Repo.get!(KuraDeployment, deployment.id)
IO.puts("→ final deployment status: #{final.status}")
IO.puts("→ started_at: #{inspect(final.started_at)}")
IO.puts("→ finished_at: #{inspect(final.finished_at)}")
IO.puts("→ error_message: #{inspect(final.error_message)}")

final_server = Repo.get!(KuraServer, server.id)
IO.puts("→ final server status: #{final_server.status} url=#{final_server.url || "—"} version=#{final_server.current_image_tag || "—"}")

logs = Kura.list_log_lines(deployment.id, limit: 200)
IO.puts("→ #{length(logs)} log line(s) captured")

logs
|> Enum.take(50)
|> Enum.each(fn %{sequence: s, line: line} -> IO.puts("    [#{s}] #{line}") end)

if length(logs) > 50 do
  IO.puts("    ... (#{length(logs) - 50} more)")
end
