alias Tuist.Authentication.TokenVerificationCache
# Run in an isolated VM: MIX_ENV=test mix run --no-start verification/bcrypt_load.exs
Application.put_env(:bcrypt_elixir, :log_rounds, 12)
{:ok, _} = Application.ensure_all_started(:bcrypt_elixir)
{:ok, _} = Application.ensure_all_started(:cachex)

{:ok, supervisor} = Supervisor.start_link([{TokenVerificationCache, cache: :bcrypt_load}], strategy: :one_for_one)
secret = Base.encode64(:crypto.strong_rand_bytes(20))
hash = Bcrypt.hash_pwd_salt(secret)
parent = self()

observer =
  spawn(fn ->
    count = fn count, n ->
      receive do
        {:trace, _, :call, {Bcrypt, :verify_pass, _}} ->
          count.(count, n + 1)

        {:count, caller} ->
          send(caller, {:bcrypt_calls, n})
          count.(count, n)
      end
    end

    count.(count, 0)
  end)

:erlang.trace_pattern({Bcrypt, :verify_pass, 2}, true, [:local])
:erlang.trace(:all, true, [:call, :set_on_spawn, {:tracer, observer}])

try do
  {duration, results} =
    :timer.tc(fn ->
      1..2_000
      |> Task.async_stream(fn _ -> TokenVerificationCache.verify_pass(secret, hash, cache: :bcrypt_load) end,
        max_concurrency: 64,
        timeout: 10_000
      )
      |> Enum.to_list()
    end)

  true = Enum.all?(results, &(&1 == {:ok, true}))
  # All fetches have completed. Flush the trace delivery before reading counts.
  ref = :erlang.trace_delivered(:all)

  receive do
    {:trace_delivered, :all, ^ref} -> :ok
  end

  send(observer, {:count, parent})

  receive do
    {:bcrypt_calls, 1} -> :ok
    {:bcrypt_calls, count} -> raise "Expected one bcrypt verification, got #{count}"
  after
    1_000 -> raise "Bcrypt observer timed out"
  end

  if duration > 10_000_000, do: raise("Cached token burst took more than 10 seconds")
  IO.puts("PASS: 2000 requests, concurrency 64, bcrypt rounds 12, exactly one verification, #{div(duration, 1000)} ms")
after
  :erlang.trace(:all, false, [:call, :set_on_spawn])
  :erlang.trace_pattern({Bcrypt, :verify_pass, 2}, false, [:local])
  Process.exit(observer, :kill)
  Supervisor.stop(supervisor)
end
