defmodule Tuist.Kura.ServerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "status enum" do
    test "keeps persisted integer values stable" do
      assert Ecto.Enum.mappings(Server, :status) == [
               provisioning: 0,
               active: 1,
               failed: 2,
               destroying: 3,
               destroyed: 4,
               replicating: 5,
               drain_pending: 6,
               archived: 7
             ]
    end
  end

  describe "lifecycle_changeset/2" do
    test "allows the demand-driven lifecycle transitions" do
      for {from, to} <- [
            {:active, :drain_pending},
            {:drain_pending, :active},
            {:drain_pending, :archived},
            {:drain_pending, :destroying},
            {:archived, :provisioning},
            {:archived, :destroying}
          ] do
        changeset =
          Server.lifecycle_changeset(
            %Server{status: from, url: "https://cache.example.com", current_image_tag: "0.5.2"},
            %{status: to}
          )

        assert changeset.valid?, "expected #{from} -> #{to} to be allowed"
      end
    end

    test "rejects skipping the drain" do
      changeset = Server.lifecycle_changeset(%Server{status: :active}, %{status: :archived})

      refute changeset.valid?
      assert %{status: ["cannot transition from active to archived"]} = errors_on(changeset)
    end

    test "rejects archiving an instance that was never drained" do
      for from <- [:provisioning, :replicating, :failed, :destroying, :destroyed] do
        changeset = Server.lifecycle_changeset(%Server{status: from}, %{status: :archived})

        refute changeset.valid?, "expected #{from} -> archived to be rejected"
      end
    end

    test "rejects draining an instance that is not serving" do
      for from <- [:provisioning, :replicating, :failed, :archived, :destroying, :destroyed] do
        changeset = Server.lifecycle_changeset(%Server{status: from}, %{status: :drain_pending})

        refute changeset.valid?, "expected #{from} -> drain_pending to be rejected"
      end
    end

    test "rejects resurrecting a destroyed instance as archived" do
      changeset = Server.lifecycle_changeset(%Server{status: :destroyed}, %{status: :provisioning})

      refute changeset.valid?
    end

    test "clears the observation columns when archiving" do
      changeset =
        Server.lifecycle_changeset(
          %Server{
            status: :drain_pending,
            url: "https://cache.example.com",
            current_image_tag: "0.5.2",
            observed_image_tag: "0.5.2"
          },
          %{status: :archived, url: nil, current_image_tag: nil, observed_image_tag: nil}
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :url) == nil
      assert Ecto.Changeset.get_field(changeset, :current_image_tag) == nil
      assert Ecto.Changeset.get_field(changeset, :observed_image_tag) == nil
    end
  end

  describe "create_changeset/2" do
    test "requires account id, region, and provisioner ref" do
      changeset = Server.create_changeset(%{})

      refute changeset.valid?

      assert %{
               account_id: ["can't be blank"],
               provisioner_node_ref: ["can't be blank"],
               region: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "accepts valid create attrs" do
      changeset =
        Server.create_changeset(%{
          account_id: account_id(),
          region: "local-controller",
          provisioner_node_ref: "kura-tuist-local-controller"
        })

      assert changeset.valid?
    end

    test "accepts a disk footprint" do
      changeset =
        Server.create_changeset(%{
          account_id: account_id(),
          region: "local-controller",
          provisioner_node_ref: "kura-tuist-local-controller",
          storage_claim_size: "24Gi",
          storage_replicas: 1
        })

      assert changeset.valid?
    end

    test "rejects a footprint the manifest could not render" do
      # Only the paths that create the volumes write one, so a claim the
      # provisioner would raise on is a bug where it is pinned.
      for claim_size <- ["24 Gi", "24GB", "0Gi", "big"] do
        changeset =
          Server.create_changeset(%{
            account_id: account_id(),
            region: "local-controller",
            provisioner_node_ref: "kura-tuist-local-controller",
            storage_claim_size: claim_size
          })

        refute changeset.valid?, "expected #{claim_size} to be rejected"
        assert %{storage_claim_size: ["must be a Kubernetes storage quantity like 24Gi"]} = errors_on(changeset)
      end

      changeset =
        Server.create_changeset(%{
          account_id: account_id(),
          region: "local-controller",
          provisioner_node_ref: "kura-tuist-local-controller",
          storage_replicas: 0
        })

      refute changeset.valid?
      assert %{storage_replicas: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "rejects unknown regions" do
      changeset =
        Server.create_changeset(%{
          account_id: account_id(),
          region: "moon",
          provisioner_node_ref: "kura-tuist-moon"
        })

      refute changeset.valid?
      assert %{region: ["is not a registered region"]} = errors_on(changeset)
    end

    test "rejects provisioner refs that are not Kubernetes label safe" do
      for provisioner_node_ref <- ["kura_tuist_local", "kura.tuist.local", String.duplicate("a", 54)] do
        changeset =
          Server.create_changeset(%{
            account_id: account_id(),
            region: "local-controller",
            provisioner_node_ref: provisioner_node_ref
          })

        refute changeset.valid?
        assert %{provisioner_node_ref: [_]} = errors_on(changeset)
      end
    end

    test "ignores lifecycle fields on create" do
      changeset =
        Server.create_changeset(%{
          account_id: account_id(),
          region: "local-controller",
          provisioner_node_ref: "kura-tuist-local-controller",
          status: :active,
          url: "https://cache.example.com",
          current_image_tag: "0.5.2"
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :status)
      refute Ecto.Changeset.get_change(changeset, :url)
      refute Ecto.Changeset.get_change(changeset, :current_image_tag)
    end

    test "database rejects status integers outside known enum values" do
      account_id = account_id()

      assert_raise Postgrex.Error, ~r/kura_servers_status_valid/, fn ->
        Repo.transaction(fn ->
          insert_raw_server!(account_id, status: 99)
        end)
      end
    end

    test "enforces the account foreign key in the database" do
      assert {:error, changeset} =
               %{
                 account_id: -1,
                 region: "local-controller",
                 provisioner_node_ref: "kura-tuist-local-controller"
               }
               |> Server.create_changeset()
               |> Repo.insert()

      assert %{account_id: ["does not exist"]} = errors_on(changeset)
    end

    test "enforces one non-destroyed server per account and region" do
      account_id = account_id()
      insert_server!(account_id)

      assert {:error, changeset} =
               %{
                 account_id: account_id,
                 region: "local-controller",
                 provisioner_node_ref: "kura-tuist-local-controller-2"
               }
               |> Server.create_changeset()
               |> Repo.insert()

      assert %{account_id: ["an active Kura server already exists for this account and region"]} =
               errors_on(changeset)
    end

    test "allows a new server when the previous server for the region is destroyed" do
      account_id = account_id()
      server = insert_server!(account_id)

      server
      |> Server.status_changeset(%{status: :destroying})
      |> Repo.update!()
      |> Server.status_changeset(%{status: :destroyed})
      |> Repo.update!()

      assert {:ok, %Server{status: :provisioning}} =
               %{
                 account_id: account_id,
                 region: "local-controller",
                 provisioner_node_ref: "kura-tuist-local-controller-2"
               }
               |> Server.create_changeset()
               |> Repo.insert()
    end
  end

  describe "status_changeset/2" do
    test "rejects unknown statuses" do
      changeset = Server.status_changeset(%Server{}, %{status: :unknown})

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "casts status updates from string params" do
      changeset = Server.status_changeset(%Server{status: :provisioning}, %{status: "failed"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == :failed
    end

    test "requires url and current image tag when activating" do
      changeset = Server.status_changeset(%Server{status: :provisioning}, %{status: :active})

      refute changeset.valid?
      assert %{current_image_tag: ["can't be blank"], url: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates current image tag when present" do
      changeset =
        Server.status_changeset(%Server{status: :provisioning}, %{
          status: :active,
          url: "https://cache.example.com",
          current_image_tag: "0.5.2+build.1"
        })

      refute changeset.valid?

      assert %{current_image_tag: ["must be a valid OCI image tag like sha-abcdef123456, latest, or 0.5.2"]} =
               errors_on(changeset)
    end

    test "allows expected status transitions" do
      transitions = [
        {:provisioning, :provisioning},
        {:provisioning, :active},
        {:provisioning, :failed},
        {:provisioning, :destroying},
        {:active, :active},
        {:active, :failed},
        {:active, :destroying},
        {:failed, :failed},
        {:failed, :provisioning},
        {:failed, :active},
        {:failed, :destroying},
        {:destroying, :destroying},
        {:destroying, :destroyed},
        {:destroyed, :destroyed}
      ]

      for {from, to} <- transitions do
        assert from
               |> server_for_transition()
               |> Server.status_changeset(valid_status_attrs(to))
               |> then(& &1.valid?)
      end
    end

    test "rejects skipped and terminal status transitions" do
      transitions = [
        {:provisioning, :destroyed},
        {:active, :provisioning},
        {:active, :destroyed},
        {:failed, :destroyed},
        {:destroying, :active},
        {:destroyed, :active}
      ]

      for {from, to} <- transitions do
        changeset =
          from
          |> server_for_transition()
          |> Server.status_changeset(valid_status_attrs(to))

        expected_error = "cannot transition from #{from} to #{to}"

        refute changeset.valid?
        assert %{status: [^expected_error]} = errors_on(changeset)
      end
    end
  end

  defp account_id do
    AccountsFixtures.account_fixture().id
  end

  defp insert_server!(account_id) do
    %{
      account_id: account_id,
      region: "local-controller",
      provisioner_node_ref: "kura-tuist-local-controller"
    }
    |> Server.create_changeset()
    |> Repo.insert!()
  end

  defp insert_raw_server!(account_id, overrides) do
    now = DateTime.utc_now()

    values =
      Map.merge(
        %{
          id: Ecto.UUID.dump!(Ecto.UUID.generate()),
          account_id: account_id,
          region: "local-controller",
          status: 0,
          provisioner_node_ref: "kura-tuist-local-controller",
          inserted_at: now,
          updated_at: now
        },
        Map.new(overrides)
      )

    Repo.query!(
      """
      INSERT INTO kura_servers
      (id, account_id, region, status, provisioner_node_ref, inserted_at, updated_at)
      VALUES ($1::uuid, $2, $3, $4, $5, $6::timestamptz, $7::timestamptz)
      """,
      [
        values.id,
        values.account_id,
        values.region,
        values.status,
        values.provisioner_node_ref,
        values.inserted_at,
        values.updated_at
      ]
    )
  end

  defp server_for_transition(status) do
    %Server{
      status: status,
      url: "https://cache.example.com",
      current_image_tag: "0.5.2"
    }
  end

  defp valid_status_attrs(:active) do
    %{status: :active, url: "https://cache.example.com", current_image_tag: "0.5.2"}
  end

  defp valid_status_attrs(status), do: %{status: status}
end
