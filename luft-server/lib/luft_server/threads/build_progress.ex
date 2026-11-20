defmodule LuftServer.Threads.BuildProgress do
  @moduledoc false

  def normalize(%{"v" => 1, "command" => command, "state" => state} = snapshot)
      when command in ["build", "test"] and state in ["running", "succeeded", "failed"] do
    tests = if is_map(snapshot["tests"]), do: snapshot["tests"], else: %{}

    {:ok,
     %{
       "command" => command,
       "state" => state,
       "target" => text(snapshot["target"]),
       "planned" => count(snapshot["planned"]),
       "done" => count(snapshot["done"]),
       "cached" => count(snapshot["cached"]),
       "failed" => count(snapshot["failed"]),
       "running" =>
         if(is_list(snapshot["running"]),
           do:
             snapshot["running"] |> Enum.filter(&is_binary/1) |> Enum.take(5) |> Enum.map(&text/1),
           else: []
         ),
       "tests" => Map.new(~w(passed failed skipped), &{&1, count(tests[&1])})
     }}
  end

  def normalize(_), do: :error

  def due?(%{progress: current}, progress) when current == progress, do: false

  def due?(%{progress: current, updated_at: updated_at}, progress) do
    milestone = ~w(command state target planned)

    not is_map(current) or Map.take(current, milestone) != Map.take(progress, milestone) or
      DateTime.diff(DateTime.utc_now(), updated_at) >= 5
  end

  def body(%{"command" => command, "target" => target} = progress) do
    verb = if command == "test", do: "Testing", else: "Building"
    subject = if target == "", do: verb, else: "#{verb} #{target}"

    targets =
      if progress["planned"] > 0,
        do:
          "#{progress["done"]} of #{progress["planned"]} targets (#{progress["cached"]} cached)",
        else: "#{progress["done"]} targets"

    tests = progress["tests"]

    cases =
      if tests["passed"] + tests["failed"] + tests["skipped"] > 0,
        do:
          " · #{tests["passed"]} passed, #{tests["failed"]} failed, #{tests["skipped"]} skipped",
        else: ""

    "#{subject} with Struo · #{targets}#{cases}"
  end

  defp count(value) when is_integer(value) and value >= 0, do: min(value, 1_000_000_000)
  defp count(_), do: 0

  defp text(value) when is_binary(value),
    do: value |> String.replace(~r/[\p{Cc}\p{Cf}]/u, "") |> String.slice(0, 200)

  defp text(_), do: ""
end
