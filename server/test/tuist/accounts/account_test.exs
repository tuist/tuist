defmodule Tuist.AccountTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User

  test "account is created when customer_id is present and billing is enabled" do
    # Given
    changeset =
      Account.create_changeset(%Account{}, %{
        name: "Test",
        user_id: 1,
        customer_id: "cus_123",
        billing_email: "#{UUIDv7.generate()}@tuist.dev"
      })

    assert changeset.valid? == true
  end

  test "name cannot contain dots" do
    changeset =
      Account.create_changeset(%Account{}, %{name: "my.name", user_id: 1})

    assert changeset.valid? == false
    assert "must contain only alphanumeric characters" in errors_on(changeset).name
  end

  describe "handle validity" do
    test "it fails the validation if a handle is included in the block list" do
      changeset =
        Account.create_changeset(%Account{}, %{
          name: Enum.random(Application.get_env(:tuist, :blocked_handles))
        })

      assert changeset.valid? == false
      assert "is reserved" in errors_on(changeset).name
    end
  end

  describe "user_id and organization_id validity" do
    test "changeset is valid when user_id is present" do
      changeset =
        Account.create_changeset(%Account{}, %{
          name: "Test",
          user_id: 1,
          customer_id: "cus_123",
          billing_email: "#{UUIDv7.generate()}@tuist.dev"
        })

      assert changeset.valid? == true
    end

    test "changeset is valid when organization_id is present" do
      changeset =
        Account.create_changeset(%Account{}, %{
          name: "Test",
          organization_id: 1,
          customer_id: "cus_123",
          billing_email: "#{UUIDv7.generate()}@tuist.dev"
        })

      assert changeset.valid? == true
    end

    test "only one of user_id or organization_id can be present" do
      changeset =
        Account.create_changeset(%Account{}, %{name: "Test", user_id: 1, organization_id: 1})

      assert changeset.valid? == false

      assert ["only one of user_id or organization_id can be present"] ==
               errors_on(changeset).organization_id

      assert ["only one of user_id or organization_id can be present"] ==
               errors_on(changeset).user_id
    end

    test "user_id or organization_id must be specified" do
      changeset =
        Account.create_changeset(%Account{}, %{name: "Test"})

      assert changeset.valid? == false
      assert ["can't be blank"] == errors_on(changeset).organization_id
    end
  end

  describe "update_changeset/2" do
    test "validates name format" do
      assert Account.update_changeset(%Account{}, %{name: "myname"}).valid?
      refute Account.update_changeset(%Account{}, %{name: "my.name"}).valid?
    end

    test "allows updating namespace_tenant_id" do
      changeset = Account.update_changeset(%Account{}, %{namespace_tenant_id: "tenant-123"})
      assert changeset.valid?
      assert changeset.changes.namespace_tenant_id == "tenant-123"
    end

    test "validates region inclusion" do
      assert Account.update_changeset(%Account{}, %{region: :all}).valid?
      assert Account.update_changeset(%Account{}, %{region: :europe}).valid?
      assert Account.update_changeset(%Account{}, %{region: :usa}).valid?

      changeset = Account.update_changeset(%Account{}, %{region: :invalid})
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).region
    end
  end

  describe "create_changeset/2" do
    test "valid name passes all validations" do
      changeset =
        Account.create_changeset(%Account{}, %{
          name: "valid-name123",
          user_id: 1,
          billing_email: "#{UUIDv7.generate()}@tuist.dev"
        })

      assert changeset.valid?
    end

    test "rejects names with invalid characters" do
      invalid_names = [
        # underscore not allowed
        "invalid_name",
        # space not allowed
        "invalid name",
        # special character not allowed
        "invalid!name",
        # special character not allowed
        "invalid@name",
        # period not allowed
        "invalid.name"
      ]

      for name <- invalid_names do
        changeset = Account.create_changeset(%Account{}, %{name: name, user_id: 1})
        assert "must contain only alphanumeric characters" in errors_on(changeset).name
      end
    end

    test "name is valid if it contains just one character" do
      changeset =
        Account.create_changeset(%Account{}, %{name: "a", user_id: 1, billing_email: "#{UUIDv7.generate()}@tuist.dev"})

      assert changeset.valid? == true
    end

    test "rejects names that are too long" do
      long_name = String.duplicate("a", 33)
      changeset = Account.create_changeset(%Account{}, %{name: long_name, user_id: 1})
      assert "should be at most 32 character(s)" in errors_on(changeset).name
    end

    test "validates namespace_tenant_id uniqueness on update" do
      {:ok, user1} = Tuist.Repo.insert(%User{email: "user1@test.com", token: "token-a"})
      {:ok, user2} = Tuist.Repo.insert(%User{email: "user2@test.com", token: "token-b"})

      {:ok, account1} =
        %Account{}
        |> Account.create_changeset(%{
          name: "account1",
          user_id: user1.id,
          billing_email: "#{UUIDv7.generate()}@tuist.dev"
        })
        |> Tuist.Repo.insert()

      {:ok, account2} =
        %Account{}
        |> Account.create_changeset(%{
          name: "account2",
          user_id: user2.id,
          billing_email: "#{UUIDv7.generate()}@tuist.dev"
        })
        |> Tuist.Repo.insert()

      Tuist.Repo.update(Account.update_changeset(account1, %{namespace_tenant_id: "tenant-123"}))
      changeset = Account.update_changeset(account2, %{namespace_tenant_id: "tenant-123"})
      {:error, changeset} = Tuist.Repo.update(changeset)
      assert "has already been taken" in errors_on(changeset).namespace_tenant_id
    end
  end

  describe "s3_storage_changeset/2" do
    test "valid when all required S3 fields are provided" do
      changeset =
        Account.s3_storage_changeset(%Account{}, %{
          s3_bucket_name: "my-bucket",
          s3_access_key_id: "AKIAIOSFODNN7EXAMPLE",
          s3_secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        })

      assert changeset.valid?
    end

    test "valid when all S3 fields including optional ones are provided" do
      changeset =
        Account.s3_storage_changeset(%Account{}, %{
          s3_bucket_name: "my-bucket",
          s3_access_key_id: "AKIAIOSFODNN7EXAMPLE",
          s3_secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
          s3_region: "us-west-2",
          s3_endpoint: "https://s3.us-west-2.amazonaws.com"
        })

      assert changeset.valid?
    end

    test "valid when no S3 fields are provided (default storage)" do
      changeset = Account.s3_storage_changeset(%Account{}, %{})
      assert changeset.valid?
    end

    test "invalid when only bucket_name is provided" do
      changeset =
        Account.s3_storage_changeset(%Account{}, %{
          s3_bucket_name: "my-bucket"
        })

      refute changeset.valid?
      assert "is required when configuring custom S3 storage" in errors_on(changeset).s3_access_key_id
      assert "is required when configuring custom S3 storage" in errors_on(changeset).s3_secret_access_key
    end

    test "invalid when only access_key_id is provided" do
      changeset =
        Account.s3_storage_changeset(%Account{}, %{
          s3_access_key_id: "AKIAIOSFODNN7EXAMPLE"
        })

      refute changeset.valid?
      assert "is required when configuring custom S3 storage" in errors_on(changeset).s3_bucket_name
      assert "is required when configuring custom S3 storage" in errors_on(changeset).s3_secret_access_key
    end

    test "invalid when bucket_name is too short" do
      changeset =
        Account.s3_storage_changeset(%Account{}, %{
          s3_bucket_name: "ab",
          s3_access_key_id: "AKIAIOSFODNN7EXAMPLE",
          s3_secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        })

      refute changeset.valid?
      assert "should be at least 3 character(s)" in errors_on(changeset).s3_bucket_name
    end

    test "invalid when bucket_name is too long" do
      changeset =
        Account.s3_storage_changeset(%Account{}, %{
          s3_bucket_name: String.duplicate("a", 64),
          s3_access_key_id: "AKIAIOSFODNN7EXAMPLE",
          s3_secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        })

      refute changeset.valid?
      assert "should be at most 63 character(s)" in errors_on(changeset).s3_bucket_name
    end

    test "invalid when bucket_name has uppercase letters" do
      changeset =
        Account.s3_storage_changeset(%Account{}, %{
          s3_bucket_name: "My-Bucket",
          s3_access_key_id: "AKIAIOSFODNN7EXAMPLE",
          s3_secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        })

      refute changeset.valid?

      assert "must be a valid S3 bucket name (lowercase letters, numbers, hyphens, and periods)" in errors_on(changeset).s3_bucket_name
    end

    test "invalid when bucket_name starts with a period" do
      changeset =
        Account.s3_storage_changeset(%Account{}, %{
          s3_bucket_name: ".my-bucket",
          s3_access_key_id: "AKIAIOSFODNN7EXAMPLE",
          s3_secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        })

      refute changeset.valid?

      assert "must be a valid S3 bucket name (lowercase letters, numbers, hyphens, and periods)" in errors_on(changeset).s3_bucket_name
    end

    test "invalid when s3_endpoint is not a valid URL" do
      changeset =
        Account.s3_storage_changeset(%Account{}, %{
          s3_bucket_name: "my-bucket",
          s3_access_key_id: "AKIAIOSFODNN7EXAMPLE",
          s3_secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
          s3_endpoint: "not-a-url"
        })

      refute changeset.valid?
      assert "must be a valid URL with http or https scheme" in errors_on(changeset).s3_endpoint
    end

    test "invalid when s3_endpoint has unsupported scheme" do
      changeset =
        Account.s3_storage_changeset(%Account{}, %{
          s3_bucket_name: "my-bucket",
          s3_access_key_id: "AKIAIOSFODNN7EXAMPLE",
          s3_secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
          s3_endpoint: "ftp://s3.example.com"
        })

      refute changeset.valid?
      assert "must be a valid URL with http or https scheme" in errors_on(changeset).s3_endpoint
    end

    test "valid with http endpoint for local development" do
      changeset =
        Account.s3_storage_changeset(%Account{}, %{
          s3_bucket_name: "my-bucket",
          s3_access_key_id: "AKIAIOSFODNN7EXAMPLE",
          s3_secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
          s3_endpoint: "http://localhost:9000"
        })

      assert changeset.valid?
    end

    test "allows clearing S3 configuration by setting all fields to nil" do
      account = %Account{
        s3_bucket_name: "my-bucket",
        s3_access_key_id: "AKIAIOSFODNN7EXAMPLE",
        s3_secret_access_key: "secret"
      }

      changeset =
        Account.s3_storage_changeset(account, %{
          s3_bucket_name: nil,
          s3_access_key_id: nil,
          s3_secret_access_key: nil,
          s3_region: nil,
          s3_endpoint: nil
        })

      assert changeset.valid?
    end
  end
end
