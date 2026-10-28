defmodule TuistEx.Analytics.Quarantine do
  @moduledoc false

  # The tests the project quarantines in Tuist. Muted tests run, and a run
  # whose only failures are muted ones passes. Skipped tests are left out of
  # the run.
  #
  # A test is identified the way the formatter reports it: the module as
  # `inspect/1` prints it, the describe block ("" outside one), and the
  # test's own name, without ExUnit's type and describe prefixes.
  #
  # ExUnit filters match one tag at a time, so a skipped test is excluded by
  # its full name (`test:"test <describe> <name>"`), the only tag that names
  # it. A test of the same full name in another module is excluded with it,
  # and a test of another type (`property`, `feature`) is not excluded; the
  # formatter names both after the run.

  alias TuistEx.Analytics.HTTP
  alias TuistEx.Analytics.Isolated

  defstruct muted: MapSet.new(), skipped: MapSet.new()

  @page_size 500
  # The same bound the command line tool applies to a Bazel policy: a policy
  # is applied whole or not at all.
  @max_cases 20_000

  @doc """
  Reads every quarantined test of the project. Returns `{:ok, policy}`, or
  `{:error, reason}` when any page could not be read: a partial policy is
  never applied. `options[:request]` stands in for `HTTP.project_request/4`.
  """
  def fetch(options) do
    case Isolated.run(fn -> fetch_pages(options, 1, []) end, 120_000) do
      {:ok, cases} -> {:ok, from_cases(cases)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_pages(options, page, fetched) do
    path = "/tests/test-cases?quarantined=true&page=#{page}&page_size=#{@page_size}"

    request = Keyword.get(options, :request, &HTTP.project_request/4)

    case request.(:get, path, nil, options) do
      {:ok, %{"test_cases" => cases} = body} when is_list(cases) ->
        fetched = fetched ++ cases
        total_pages = get_in(body, ["pagination_metadata", "total_pages"])

        cond do
          length(fetched) > @max_cases ->
            {:error, :too_many_test_cases}

          is_integer(total_pages) and page < total_pages ->
            fetch_pages(options, page + 1, fetched)

          true ->
            {:ok, fetched}
        end

      {:ok, _body} ->
        {:error, :unexpected_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def from_cases(cases) do
    Enum.reduce(cases, %__MODULE__{}, fn
      %{"state" => state, "name" => name, "module" => %{"name" => module}} = test_case, policy
      when state in ["muted", "skipped"] and is_binary(name) and is_binary(module) ->
        suite =
          case test_case["suite"] do
            %{"name" => suite} when is_binary(suite) -> suite
            _ -> ""
          end

        key = if state == "muted", do: :muted, else: :skipped
        Map.update!(policy, key, &MapSet.put(&1, {module, suite, name}))

      _test_case, policy ->
        policy
    end)
  end

  def empty?(%__MODULE__{muted: muted, skipped: skipped}),
    do: MapSet.size(muted) == 0 and MapSet.size(skipped) == 0

  @doc """
  The `mix test` arguments that leave the skipped tests out.
  """
  def exclude_args(policy) do
    policy |> excluded_names() |> Enum.sort() |> Enum.flat_map(&["--exclude", "test:" <> &1])
  end

  @doc """
  The full ExUnit names of the skipped tests, as `test.name` holds them.
  """
  def excluded_names(%__MODULE__{skipped: skipped}) do
    MapSet.new(skipped, fn
      {_module, "", name} -> "test " <> name
      {_module, suite, name} -> "test " <> suite <> " " <> name
    end)
  end

  def excluded_names(nil), do: MapSet.new()

  def identity(%{module: module, describe: describe, name: name}),
    do: {module, describe || "", name}

  def muted?(%__MODULE__{muted: muted}, identity), do: MapSet.member?(muted, identity)
  def muted?(nil, _identity), do: false

  def skipped?(%__MODULE__{skipped: skipped}, identity), do: MapSet.member?(skipped, identity)
  def skipped?(nil, _identity), do: false

  def quarantined?(policy, identity), do: muted?(policy, identity) or skipped?(policy, identity)

  @doc """
  Whether a run failed only because of muted tests: it has failed tests, and
  every one of them is muted.
  """
  def only_muted_failed?(payload, policy) do
    failed =
      for module <- payload.test_modules,
          test_case <- module.test_cases,
          test_case.status == "failure",
          do: {module.name, Map.get(test_case, :test_suite_name) || "", test_case.name}

    failed != [] and Enum.all?(failed, &muted?(policy, &1))
  end

  def describe({module, "", name}), do: "#{module}: #{name}"
  def describe({module, suite, name}), do: "#{module}: #{suite} #{name}"
end
