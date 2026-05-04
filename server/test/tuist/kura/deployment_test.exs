defmodule Tuist.Kura.DeploymentTest do
  use ExUnit.Case, async: false
  use TuistTestSupport.Cases.DataCase

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
      account = then(AccountsFixtures.user_fixture(), & &1.account)

      server =
        %Server{}
        |> Server.create_changeset(%{
          account_id: account.id,
          region: "local",
          spec: :small,
          volume_size_gi: 50,
          provisioner_node_ref: "kura-#{account.name}-local"
        })
        |> Repo.insert!()

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
end
