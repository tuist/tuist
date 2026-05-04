defmodule Tuist.Kura.ServerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "spec enum" do
    test "keeps persisted integer values stable" do
      assert Ecto.Enum.mappings(Server, :spec) == [
               small: 0,
               medium: 1,
               large: 2
             ]
    end
  end

  describe "status enum" do
    test "keeps persisted integer values stable" do
      assert Ecto.Enum.mappings(Server, :status) == [
               provisioning: 0,
               active: 1,
               failed: 2,
               destroying: 3,
               destroyed: 4
             ]
    end
  end

  describe "create_changeset/2" do
    test "requires account id, region, volume size, and provisioner ref" do
      changeset = Server.create_changeset(%{})

      refute changeset.valid?

      assert %{
               account_id: ["can't be blank"],
               provisioner_node_ref: ["can't be blank"],
               region: ["can't be blank"],
               volume_size_gi: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "defaults spec to medium" do
      changeset =
        Server.create_changeset(%{
          account_id: account_id(),
          region: "local",
          volume_size_gi: 200,
          provisioner_node_ref: "kura-tuist-local"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :spec) == :medium
    end

    test "casts supported specs from string params" do
      changeset =
        Server.create_changeset(%{
          account_id: account_id(),
          region: "local",
          spec: "small",
          volume_size_gi: 50,
          provisioner_node_ref: "kura-tuist-local"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :spec) == :small
    end

    test "rejects unknown specs" do
      changeset =
        Server.create_changeset(%{
          account_id: account_id(),
          region: "local",
          spec: :xlarge,
          volume_size_gi: 50,
          provisioner_node_ref: "kura-tuist-local"
        })

      refute changeset.valid?
      assert %{spec: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects unknown regions" do
      changeset =
        Server.create_changeset(%{
          account_id: account_id(),
          region: "moon",
          spec: :small,
          volume_size_gi: 50,
          provisioner_node_ref: "kura-tuist-moon"
        })

      refute changeset.valid?
      assert %{region: ["is not a registered region"]} = errors_on(changeset)
    end

    test "rejects invalid volume sizes" do
      for volume_size_gi <- [0, 10_001] do
        changeset =
          Server.create_changeset(%{
            account_id: account_id(),
            region: "local",
            spec: :small,
            volume_size_gi: volume_size_gi,
            provisioner_node_ref: "kura-tuist-local"
          })

        refute changeset.valid?
        assert %{volume_size_gi: [_]} = errors_on(changeset)
      end
    end

    test "ignores lifecycle fields on create" do
      changeset =
        Server.create_changeset(%{
          account_id: account_id(),
          region: "local",
          spec: :small,
          volume_size_gi: 50,
          provisioner_node_ref: "kura-tuist-local",
          status: :active,
          url: "https://cache.example.com",
          current_image_tag: "0.5.2"
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :status)
      refute Ecto.Changeset.get_change(changeset, :url)
      refute Ecto.Changeset.get_change(changeset, :current_image_tag)
    end

    test "database constrains persisted spec and status integers" do
      for {name, values} <- [
            {"kura_servers_spec_valid", 0..2},
            {"kura_servers_status_valid", 0..4}
          ] do
        %{rows: [[definition]]} =
          Repo.query!(
            """
            SELECT pg_get_constraintdef(oid)
            FROM pg_constraint
            WHERE conrelid = 'kura_servers'::regclass
            AND conname = $1
            """,
            [name]
          )

        for value <- values do
          assert definition =~ Integer.to_string(value)
        end
      end
    end

    test "database rejects spec integers outside known enum values" do
      account_id = account_id()

      assert_raise Postgrex.Error, ~r/kura_servers_spec_valid/, fn ->
        Repo.transaction(fn ->
          insert_raw_server!(account_id, spec: 99)
        end)
      end
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
                 region: "local",
                 spec: :small,
                 volume_size_gi: 50,
                 provisioner_node_ref: "kura-tuist-local"
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
                 region: "local",
                 spec: :small,
                 volume_size_gi: 50,
                 provisioner_node_ref: "kura-tuist-local-2"
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
                 region: "local",
                 spec: :small,
                 volume_size_gi: 50,
                 provisioner_node_ref: "kura-tuist-local-2"
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

      assert %{current_image_tag: ["must be a Kura image tag like 0.5.2, 0.5.2-rc.1, or v0.5.2"]} =
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
        {:failed, :provisioning},
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
      region: "local",
      spec: :small,
      volume_size_gi: 50,
      provisioner_node_ref: "kura-tuist-local"
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
          region: "local",
          spec: 0,
          volume_size_gi: 50,
          status: 0,
          provisioner_node_ref: "kura-tuist-local",
          inserted_at: now,
          updated_at: now
        },
        Map.new(overrides)
      )

    Repo.query!(
      """
      INSERT INTO kura_servers
      (id, account_id, region, spec, volume_size_gi, status, provisioner_node_ref, inserted_at, updated_at)
      VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8::timestamptz, $9::timestamptz)
      """,
      [
        values.id,
        values.account_id,
        values.region,
        values.spec,
        values.volume_size_gi,
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
