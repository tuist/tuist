defmodule Tuist.Kura.DeploymentTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "status enum" do
    test "keeps persisted integer values stable" do
      assert Ecto.Enum.mappings(Deployment, :status) == [
               pending: 0,
               running: 1,
               succeeded: 2,
               failed: 3,
               cancelled: 4
             ]
    end
  end

  describe "create_changeset/2" do
    test "requires cluster id, image tag, and server id" do
      changeset = Deployment.create_changeset(%{})

      refute changeset.valid?

      assert %{cluster_id: ["can't be blank"], image_tag: ["can't be blank"], kura_server_id: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "accepts deployable Kura image tags" do
      for image_tag <- ["0.5.2", "v0.5.2", "0.5.2-rc.1", "0.5.2-rc.1.2"] do
        changeset =
          Deployment.create_changeset(%{
            cluster_id: "local",
            image_tag: image_tag,
            kura_server_id: Ecto.UUID.generate()
          })

        assert changeset.valid?
      end
    end

    test "rejects tags outside the deployable Kura image tag format" do
      for image_tag <- ["latest", "0.5", "01.5.2", "0.5.2-", "0.5.2+build.1", "0.5.2\n"] do
        changeset =
          Deployment.create_changeset(%{
            cluster_id: "local",
            image_tag: image_tag,
            kura_server_id: Ecto.UUID.generate()
          })

        assert %{image_tag: ["must be a Kura image tag like 0.5.2, 0.5.2-rc.1, or v0.5.2"]} =
                 errors_on(changeset)
      end
    end

    test "rejects image tags longer than Docker allows" do
      changeset =
        Deployment.create_changeset(%{
          cluster_id: "local",
          image_tag: "0.5.2-" <> String.duplicate("a", 123),
          kura_server_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert "should be at most 128 character(s)" in errors_on(changeset).image_tag
    end

    test "ignores lifecycle fields on create" do
      changeset =
        Deployment.create_changeset(%{
          cluster_id: "local",
          image_tag: "0.5.2",
          kura_server_id: Ecto.UUID.generate(),
          status: :succeeded,
          error_message: "already done",
          oban_job_id: 123
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :status)
      refute Ecto.Changeset.get_change(changeset, :error_message)
      refute Ecto.Changeset.get_change(changeset, :oban_job_id)
    end

    test "database constrains status to known enum integers" do
      %{rows: [[definition]]} =
        Repo.query!("""
        SELECT pg_get_constraintdef(oid)
        FROM pg_constraint
        WHERE conrelid = 'kura_deployments'::regclass
        AND conname = 'kura_deployments_status_valid'
        """)

      assert definition =~ "status"

      for status <- 0..4 do
        assert definition =~ Integer.to_string(status)
      end
    end

    test "database rejects status integers outside known enum values" do
      server = insert_server()
      now = DateTime.utc_now()

      assert_raise Postgrex.Error, ~r/kura_deployments_status_valid/, fn ->
        Repo.transaction(fn ->
          Repo.query!(
            """
            INSERT INTO kura_deployments
            (id, cluster_id, image_tag, status, kura_server_id, inserted_at, updated_at)
            VALUES ($1::uuid, $2, $3, $4, $5::uuid, $6::timestamptz, $7::timestamptz)
            """,
            [Ecto.UUID.dump!(Ecto.UUID.generate()), "local", "0.5.2", 99, Ecto.UUID.dump!(server.id), now, now]
          )
        end)
      end

      assert Repo.get!(Server, server.id)
    end

    test "enforces the server foreign key in the database" do
      assert {:error, changeset} =
               %{
                 cluster_id: "local",
                 image_tag: "0.5.2",
                 kura_server_id: Ecto.UUID.generate()
               }
               |> Deployment.create_changeset()
               |> Repo.insert()

      assert %{kura_server_id: ["does not exist"]} = errors_on(changeset)
    end

    test "inserts a deployment for an existing server" do
      server = insert_server()

      deployment =
        %{
          cluster_id: "local",
          image_tag: "0.5.2",
          kura_server_id: server.id
        }
        |> Deployment.create_changeset()
        |> Repo.insert!()

      assert deployment.status == :pending
      assert deployment.cluster_id == "local"
      assert deployment.image_tag == "0.5.2"
      assert deployment.kura_server_id == server.id
    end
  end

  describe "status_changeset/2" do
    test "rejects unknown statuses" do
      changeset = Deployment.status_changeset(%Deployment{}, %{status: :unknown})

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "casts supported status updates" do
      started_at = DateTime.utc_now(:second)
      finished_at = DateTime.add(started_at, 60, :second)

      changeset =
        Deployment.status_changeset(%Deployment{status: :running}, %{
          status: :failed,
          error_message: "rollout failed",
          oban_job_id: 123,
          started_at: started_at,
          finished_at: finished_at
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == :failed
      assert Ecto.Changeset.get_change(changeset, :error_message) == "rollout failed"
      assert Ecto.Changeset.get_change(changeset, :oban_job_id) == 123
    end

    test "casts status updates from string params" do
      changeset = Deployment.status_changeset(%Deployment{status: :pending}, %{status: "running"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == :running
    end

    test "allows expected status transitions" do
      transitions = [
        {:pending, :pending},
        {:pending, :running},
        {:pending, :failed},
        {:pending, :cancelled},
        {:running, :running},
        {:running, :succeeded},
        {:running, :failed},
        {:running, :cancelled},
        {:succeeded, :succeeded},
        {:failed, :failed},
        {:cancelled, :cancelled}
      ]

      for {from, to} <- transitions do
        assert Deployment.status_changeset(%Deployment{status: from}, %{status: to}).valid?
      end
    end

    test "rejects skipped and terminal status transitions" do
      transitions = [
        {:pending, :succeeded},
        {:succeeded, :running},
        {:failed, :running},
        {:cancelled, :running}
      ]

      for {from, to} <- transitions do
        changeset = Deployment.status_changeset(%Deployment{status: from}, %{status: to})
        expected_error = "cannot transition from #{from} to #{to}"

        refute changeset.valid?
        assert %{status: [^expected_error]} = errors_on(changeset)
      end
    end
  end

  defp insert_server do
    account = then(AccountsFixtures.user_fixture(), & &1.account)

    %Server{}
    |> Server.create_changeset(%{
      account_id: account.id,
      region: "local",
      spec: :small,
      volume_size_gi: 50,
      provisioner_node_ref: "kura-#{account.name}-local"
    })
    |> Repo.insert!()
  end
end
