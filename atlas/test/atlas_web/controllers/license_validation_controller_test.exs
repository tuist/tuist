defmodule AtlasWeb.LicenseValidationControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Audit.Activity
  alias Atlas.Licenses.Issuer
  alias Atlas.Licenses.License
  alias Atlas.Licenses.RateLimiter
  alias Atlas.Repo

  # The limiter is a singleton process shared by the whole node, so these tests
  # drive it through a stub instead of the real buckets. The window arithmetic
  # itself is covered by `Atlas.Licenses.RateLimiter.BucketsTest`.
  setup do
    stub(RateLimiter, :check, fn _identifier -> :ok end)
    :ok
  end

  test "returns a Tuist-compatible response for an active online key", %{conn: conn} do
    customer = insert_account!()
    license = insert_license!(customer)

    conn = post(conn, ~p"/api/licenses/actions/validate-key", %{meta: %{key: license.key}})

    assert %{
             "data" => %{
               "id" => license_id,
               "attributes" => %{
                 "expiry" => expiry,
                 "metadata" => %{"signingKey" => signing_key}
               }
             },
             "meta" => %{"valid" => true}
           } = json_response(conn, 200)

    assert license_id == license.id
    assert expiry == Date.to_iso8601(license.expires_on) <> "T23:59:59Z"
    assert signing_key == license.signing_key

    activity = Repo.get_by!(Activity, action: "license.validated", target_id: license.id)
    assert activity.interface == "api"
  end

  test "returns no data for an unknown online key", %{conn: conn} do
    conn = post(conn, ~p"/api/licenses/actions/validate-key", %{meta: %{key: "unknown"}})

    assert %{"data" => nil, "meta" => %{"valid" => false}} = json_response(conn, 200)
  end

  test "returns an expired license as invalid and audits that outcome", %{conn: conn} do
    customer = insert_account!()
    license = insert_license!(customer, %{expires_on: Date.add(Date.utc_today(), -1)})

    conn = post(conn, ~p"/api/licenses/actions/validate-key", %{meta: %{key: license.key}})

    assert %{
             "data" => %{"id" => license_id},
             "meta" => %{"valid" => false}
           } = json_response(conn, 200)

    assert license_id == license.id
    activity = Repo.get_by!(Activity, action: "license.validated", target_id: license.id)
    assert activity.metadata["valid"] == "false"
  end

  test "requires the online key", %{conn: conn} do
    conn = post(conn, ~p"/api/licenses/actions/validate-key", %{})

    assert %{"error" => "meta.key is required"} = json_response(conn, 400)
  end

  test "rate limits repeated validation attempts for the same key without extra audit writes", %{conn: conn} do
    stub_client_rate_limit("203.0.113.10", 2)

    conn = put_req_header(conn, "x-real-ip", "203.0.113.10")
    customer = insert_account!()
    license = insert_license!(customer)

    first = post(conn, ~p"/api/licenses/actions/validate-key", %{meta: %{key: license.key}})
    second = post(conn, ~p"/api/licenses/actions/validate-key", %{meta: %{key: license.key}})
    limited = post(conn, ~p"/api/licenses/actions/validate-key", %{meta: %{key: license.key}})

    assert json_response(first, 200)["meta"]["valid"]
    assert json_response(second, 200)["meta"]["valid"]
    assert %{"error" => "rate limit exceeded"} = json_response(limited, 429)
    assert [_retry_after] = get_resp_header(limited, "retry-after")

    assert Repo.aggregate(
             from(activity in Activity,
               where: activity.action == "license.validated" and activity.target_id == ^license.id
             ),
             :count
           ) == 2
  end

  test "rate limits repeated unknown-key traffic before it can keep querying licenses", %{conn: conn} do
    stub_client_rate_limit("203.0.113.11", 2)

    conn = put_req_header(conn, "x-real-ip", "203.0.113.11")

    first = post(conn, ~p"/api/licenses/actions/validate-key", %{meta: %{key: "unknown-1"}})
    second = post(conn, ~p"/api/licenses/actions/validate-key", %{meta: %{key: "unknown-2"}})
    limited = post(conn, ~p"/api/licenses/actions/validate-key", %{meta: %{key: "unknown-3"}})

    assert %{"data" => nil, "meta" => %{"valid" => false}} = json_response(first, 200)
    assert %{"data" => nil, "meta" => %{"valid" => false}} = json_response(second, 200)
    assert %{"error" => "rate limit exceeded"} = json_response(limited, 429)
    assert [_retry_after] = get_resp_header(limited, "retry-after")
  end

  # Lets the first `max_attempts` requests from `address` through and rejects the
  # rest, so the controller sees exactly what a saturated bucket looks like.
  # Other identifiers, such as the per-license-key one, stay unlimited.
  defp stub_client_rate_limit(address, max_attempts) do
    client_identifier = :crypto.hash(:sha256, "license-validation-client:" <> address)
    attempts = :counters.new(1, [])

    stub(RateLimiter, :check, fn
      ^client_identifier ->
        :counters.add(attempts, 1, 1)

        if :counters.get(attempts, 1) > max_attempts do
          {:error, 60}
        else
          :ok
        end

      _other_identifier ->
        :ok
    end)
  end

  defp insert_account! do
    %Account{}
    |> Account.changeset(%{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Acme Labs",
      segment: :customer
    })
    |> Repo.insert!()
  end

  defp insert_license!(customer, attrs \\ %{}) do
    key = "ONLINE-KEY-#{System.unique_integer([:positive])}"

    attrs =
      Map.merge(
        %{
          key: key,
          key_hash: Issuer.key_hash(key),
          signing_key: Base.encode64(:crypto.strong_rand_bytes(32)),
          expires_on: Date.utc_today() |> Date.add(365)
        },
        attrs
      )

    %License{account_id: customer.id}
    |> License.issued_changeset(attrs)
    |> Repo.insert!()
  end
end
