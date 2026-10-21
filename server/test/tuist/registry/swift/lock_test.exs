defmodule Tuist.Registry.Swift.LockTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Registry
  alias Tuist.Registry.Swift.Lock

  setup do
    stub(Registry, :registry_bucket, fn -> "test-bucket" end)
    stub(Registry, :registry_s3_config, fn -> [] end)
    :ok
  end

  test "an expired owner cannot release its successor's lease" do
    expect(ExAws, :request, fn %{http_method: :put, body: body}, _ ->
      send(self(), {:acquired, JSON.decode!(body)})
      {:ok, %{}}
    end)

    assert {:ok, :acquired} = Lock.try_acquire(:test, 1)
    assert_receive {:acquired, acquired}
    assert acquired["owner"]
    successor = %{"owner" => Ecto.UUID.generate(), "expires_at" => System.system_time(:second) + 60}

    expect(ExAws, :request, fn %{http_method: :get}, _ ->
      {:ok, %{body: JSON.encode!(successor), headers: %{"etag" => "next"}}}
    end)

    assert :ok = Lock.release(:test)
    # No PUT or DELETE expectation: any mutation of the successor fails.
  end

  test "release conditionally expires only its own object version" do
    expect(ExAws, :request, fn %{http_method: :put, body: body}, _ ->
      send(self(), {:acquired_body, body})
      {:ok, %{}}
    end)

    assert {:ok, :acquired} = Lock.try_acquire(:test, 1)
    assert_receive {:acquired_body, acquired_body}

    expect(ExAws, :request, fn %{http_method: :get}, _ ->
      {:ok, %{body: acquired_body, headers: %{"etag" => "old"}}}
    end)

    expect(ExAws, :request, fn %{http_method: :put, body: body, headers: headers}, _ ->
      send(self(), {:released, JSON.decode!(body), headers})
      {:ok, %{}}
    end)

    assert :ok = Lock.release(:test)
    assert_receive {:released, %{"expires_at" => 0}, headers}
    assert headers["if-match"] == "\"old\""
  end
end
