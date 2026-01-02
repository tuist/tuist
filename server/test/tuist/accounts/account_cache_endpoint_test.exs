defmodule Tuist.Accounts.AccountCacheEndpointTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts.AccountCacheEndpoint

  describe "create_changeset/2" do
    test "creates valid changeset with valid attributes" do
      changeset =
        AccountCacheEndpoint.create_changeset(%{
          url: "https://cache.example.com",
          account_id: 1
        })

      assert changeset.valid?
    end

    test "requires url" do
      changeset =
        AccountCacheEndpoint.create_changeset(%{
          account_id: 1
        })

      refute changeset.valid?
      assert %{url: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires account_id" do
      changeset =
        AccountCacheEndpoint.create_changeset(%{
          url: "https://cache.example.com"
        })

      refute changeset.valid?
      assert %{account_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates URL has valid scheme" do
      changeset =
        AccountCacheEndpoint.create_changeset(%{
          url: "ftp://cache.example.com",
          account_id: 1
        })

      refute changeset.valid?
      assert %{url: ["must be a valid HTTP or HTTPS URL"]} = errors_on(changeset)
    end

    test "validates URL has host" do
      changeset =
        AccountCacheEndpoint.create_changeset(%{
          url: "https://",
          account_id: 1
        })

      refute changeset.valid?
      assert %{url: ["must be a valid HTTP or HTTPS URL"]} = errors_on(changeset)
    end

    test "accepts http URL" do
      changeset =
        AccountCacheEndpoint.create_changeset(%{
          url: "http://cache.example.com",
          account_id: 1
        })

      assert changeset.valid?
    end

    test "accepts https URL" do
      changeset =
        AccountCacheEndpoint.create_changeset(%{
          url: "https://cache.example.com",
          account_id: 1
        })

      assert changeset.valid?
    end
  end
end
