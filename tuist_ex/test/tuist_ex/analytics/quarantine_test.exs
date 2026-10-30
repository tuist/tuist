defmodule TuistEx.Analytics.QuarantineTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.Quarantine

  defp test_case(state, module, suite, name) do
    %{
      "state" => state,
      "name" => name,
      "module" => %{"id" => module, "name" => module},
      "suite" => if(suite, do: %{"id" => suite, "name" => suite})
    }
  end

  test "reads every page of quarantined tests before applying any" do
    owner = self()

    request = fn :get, path, nil, _options ->
      send(owner, {:requested, path})

      case URI.decode_query(URI.parse(path).query)["page"] do
        "1" ->
          {:ok,
           %{
             "test_cases" => [test_case("muted", "App.CartTest", "add/2", "rejects nil")],
             "pagination_metadata" => %{"total_pages" => 2}
           }}

        "2" ->
          {:ok,
           %{
             "test_cases" => [
               test_case("skipped", "App.OrderTest", nil, "ships"),
               test_case("enabled", "App.OrderTest", nil, "bills")
             ],
             "pagination_metadata" => %{"total_pages" => 2}
           }}
      end
    end

    assert {:ok, policy} = Quarantine.fetch(project: "acme/app", request: request)
    assert_received {:requested, "/tests/test-cases?quarantined=true&page=1&page_size=500"}
    assert_received {:requested, "/tests/test-cases?quarantined=true&page=2&page_size=500"}
    assert MapSet.to_list(policy.muted) == [{"App.CartTest", "add/2", "rejects nil"}]
    assert MapSet.to_list(policy.skipped) == [{"App.OrderTest", "", "ships"}]
  end

  test "applies nothing when a page cannot be read" do
    request = fn :get, path, nil, _options ->
      if path =~ "page=1&",
        do: {:ok, %{"test_cases" => [], "pagination_metadata" => %{"total_pages" => 2}}},
        else: {:error, {:http, 500, %{}}}
    end

    assert Quarantine.fetch(request: request) == {:error, {:http, 500, %{}}}
  end

  test "excludes a skipped test by the full name ExUnit gives it" do
    policy =
      Quarantine.from_cases([
        test_case("skipped", "App.OrderTest", nil, "ships"),
        test_case("skipped", "App.CartTest", "add/2", "rejects nil"),
        test_case("muted", "App.CartTest", "add/2", "flakes")
      ])

    assert Quarantine.exclude_args(policy) == [
             "--exclude",
             "test:test add/2 rejects nil",
             "--exclude",
             "test:test ships"
           ]

    assert Quarantine.exclude_args(Quarantine.from_cases([])) == []
    assert Quarantine.exclude_args(nil) == []

    # What `mix test` makes of the arguments matches the test ExUnit names.
    assert [exclude: "test:test ships"] |> Keyword.values() |> ExUnit.Filters.parse() ==
             [test: "test ships"]

    assert ExUnit.Filters.eval([], [test: "test ships"], %{test: :"test ships"}, []) ==
             {:excluded, "due to test filter"}
  end

  test "a run fails only on muted tests when every failed test is muted" do
    policy = Quarantine.from_cases([test_case("muted", "App.CartTest", "add/2", "flakes")])

    run = fn cases ->
      %{test_modules: [%{name: "App.CartTest", test_cases: cases}]}
    end

    muted = %{name: "flakes", test_suite_name: "add/2", status: "failure"}
    other = %{name: "breaks", status: "failure"}
    passing = %{name: "passes", status: "success"}

    assert Quarantine.only_muted_failed?(run.([muted, passing]), policy)
    refute Quarantine.only_muted_failed?(run.([muted, other]), policy)
    refute Quarantine.only_muted_failed?(run.([passing]), policy)
    refute Quarantine.only_muted_failed?(run.([muted]), nil)
  end
end
