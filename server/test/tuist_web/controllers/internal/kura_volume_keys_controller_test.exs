defmodule TuistWeb.Internal.KuraVolumeKeysControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.Server
  alias Tuist.Kura.VolumeKeys
  alias Tuist.Kura.VolumeKeys.HKDF
  alias Tuist.Kura.VolumeKeys.TenantKey
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.KuraFixtures
  alias TuistWeb.RateLimit

  @volume_id "pvc-0b1c2d3e"
  @node "kura-node-a"
  @claim_uid "3c0ffee0-0000-4000-8000-000000000001"
  @username "system:serviceaccount:kura-volumes:kura-volumes-csi-node"

  setup do
    root_key = :crypto.strong_rand_bytes(32)
    stub(Environment, :kura_volume_root_keys, fn -> [{"root-a", root_key}] end)

    account = AccountsFixtures.account_fixture()
    server = KuraFixtures.active_server_fixture(account)
    {client_public, client_private} = :crypto.generate_key(:ecdh, :x25519)

    stub(Client, :create_bound_token_review, fn "node-token", "kura-volume-keys.tuist.dev", _opts ->
      {:ok, %{username: @username, uid: "uid", extra: %{"authentication.kubernetes.io/node-name" => [@node]}}}
    end)

    stub(Client, :get_persistent_volume, fn @volume_id, _opts -> {:ok, persistent_volume()} end)

    stub(Client, :get_persistent_volume_claim, fn "kura", "data-kura-0", _opts ->
      {:ok, claim(server.provisioner_node_ref)}
    end)

    %{account: account, server: server, client_public: client_public, client_private: client_private}
  end

  test "issues the volume passphrase sealed to the caller", %{conn: conn, account: account} = context do
    response = conn |> request(context) |> json_response(200)

    assert response["key_version"] == 1
    passphrase = open(response, context)

    assert {:ok, ^passphrase} =
             VolumeKeys.volume_passphrase(account, Repo.get_by!(TenantKey, account_id: account.id), @volume_id)

    second = conn |> recycle() |> request(context) |> json_response(200)
    assert second["ephemeral_public_key"] != response["ephemeral_public_key"]
    assert open(second, context) == passphrase
  end

  test "serves an explicitly requested key version, and 404s an unknown one", %{conn: conn} = context do
    first = conn |> request(context) |> json_response(200)

    assert conn |> recycle() |> request(context, %{"key_version" => 1}) |> json_response(200) |> open(context) ==
             open(first, context)

    assert conn |> recycle() |> request(context, %{"key_version" => 2}) |> json_response(404) ==
             %{"error" => "key_version_not_found"}

    assert conn |> recycle() |> request(context, %{"key_version" => "1"}) |> json_response(400) ==
             %{"error" => "invalid_key_version"}
  end

  describe "authentication" do
    test "rejects a missing or rejected token", %{conn: conn} = context do
      stub(Client, :create_bound_token_review, fn _token, _audience, _opts -> {:error, :unauthenticated} end)
      reject(&Client.get_persistent_volume/2)

      assert conn |> request(context, %{}, nil) |> json_response(401) == %{"error" => "unauthenticated"}
      assert conn |> recycle() |> request(context) |> json_response(401) == %{"error" => "unauthenticated"}
    end

    test "rejects another ServiceAccount", %{conn: conn} = context do
      stub(Client, :create_bound_token_review, fn _token, _audience, _opts ->
        {:ok,
         %{
           username: "system:serviceaccount:kura:default",
           uid: "uid",
           extra: %{"authentication.kubernetes.io/node-name" => [@node]}
         }}
      end)

      assert conn |> request(context) |> json_response(401) == %{"error" => "unauthenticated"}
    end

    test "rejects a token that is not bound to exactly one node", %{conn: conn} = context do
      for extra <- [
            %{},
            %{"authentication.kubernetes.io/node-name" => []},
            %{"authentication.kubernetes.io/node-name" => [@node, "other"]}
          ] do
        stub(Client, :create_bound_token_review, fn _token, _audience, _opts ->
          {:ok, %{username: @username, uid: "uid", extra: extra}}
        end)

        assert conn |> recycle() |> request(context) |> json_response(401) == %{"error" => "unauthenticated"}
      end
    end
  end

  describe "authorization" do
    test "404s a volume that does not exist", %{conn: conn} = context do
      stub(Client, :get_persistent_volume, fn _name, _opts -> {:error, :not_found} end)
      assert conn |> request(context) |> json_response(404) == %{"error" => "volume_not_found"}
    end

    test "refuses volumes of another driver, node or namespace", %{conn: conn} = context do
      for volume <- [
            put_in(persistent_volume(), ["spec", "csi", "driver"], "local.csi.example"),
            put_in(persistent_volume(), ["spec", "csi", "volumeHandle"], "pvc-other"),
            put_in(persistent_volume(), ["spec", "claimRef", "namespace"], "default"),
            pinned_to(["other-node"]),
            pinned_to([@node, "other-node"]),
            put_in(persistent_volume(), ["spec", "nodeAffinity", "required", "nodeSelectorTerms"], [
              node_term(@node),
              node_term("other-node")
            ]),
            update_in(persistent_volume(), ["spec"], &Map.delete(&1, "nodeAffinity"))
          ] do
        stub(Client, :get_persistent_volume, fn _name, _opts -> {:ok, volume} end)
        assert conn |> recycle() |> request(context) |> json_response(403) == %{"error" => "forbidden"}
      end
    end

    test "refuses a claim that was replaced, rebound, or missing", %{conn: conn, server: server} = context do
      for claim <- [
            put_in(claim(server.provisioner_node_ref), ["metadata", "uid"], "another-uid"),
            put_in(claim(server.provisioner_node_ref), ["spec", "volumeName"], "pvc-other"),
            update_in(
              claim(server.provisioner_node_ref),
              ["metadata", "labels"],
              &Map.delete(&1, "app.kubernetes.io/instance")
            )
          ] do
        stub(Client, :get_persistent_volume_claim, fn _namespace, _name, _opts -> {:ok, claim} end)
        assert conn |> recycle() |> request(context) |> json_response(403) == %{"error" => "forbidden"}
      end

      stub(Client, :get_persistent_volume_claim, fn _namespace, _name, _opts -> {:error, :not_found} end)
      assert conn |> recycle() |> request(context) |> json_response(403) == %{"error" => "forbidden"}
    end

    test "refuses an instance no live server owns", %{conn: conn, server: server} = context do
      stub(Client, :get_persistent_volume_claim, fn _namespace, _name, _opts -> {:ok, claim("kura-unknown")} end)
      assert conn |> request(context) |> json_response(403) == %{"error" => "forbidden"}

      server |> Ecto.Changeset.change(status: :destroyed) |> Repo.update!()

      stub(Client, :get_persistent_volume_claim, fn _namespace, _name, _opts ->
        {:ok, claim(server.provisioner_node_ref)}
      end)

      assert conn |> recycle() |> request(context) |> json_response(403) == %{"error" => "forbidden"}
    end

    test "refuses an instance name two accounts claim", %{conn: conn, server: server} = context do
      other = AccountsFixtures.account_fixture()

      Repo.insert!(%Server{
        account_id: other.id,
        region: "eu-west",
        status: :provisioning,
        provisioner_node_ref: server.provisioner_node_ref
      })

      assert conn |> request(context) |> json_response(403) == %{"error" => "forbidden"}
    end
  end

  describe "input" do
    test "rejects a public key that is not 32 bytes", %{conn: conn} do
      reject(&Client.create_bound_token_review/3)

      for public_key <- [Base.encode64(:crypto.strong_rand_bytes(31)), "not base64", nil] do
        assert conn
               |> recycle()
               |> put_req_header("authorization", "Bearer node-token")
               |> post(~p"/_internal/kura/volume-keys", %{"volume_id" => @volume_id, "public_key" => public_key})
               |> json_response(400) == %{"error" => "invalid_public_key"}
      end
    end

    test "rejects a low-order public key", %{conn: conn} = context do
      assert conn |> request(%{context | client_public: <<0::256>>}) |> json_response(400) ==
               %{"error" => "invalid_public_key"}
    end

    test "rejects a volume id that is not a Kubernetes name", %{conn: conn} = context do
      reject(&Client.create_bound_token_review/3)

      for volume_id <- ["../nodes/x", "PVC", "", nil] do
        assert conn
               |> recycle()
               |> put_req_header("authorization", "Bearer node-token")
               |> post(~p"/_internal/kura/volume-keys", %{
                 "volume_id" => volume_id,
                 "public_key" => Base.encode64(context.client_public)
               })
               |> json_response(400) == %{"error" => "invalid_volume_id"}
      end
    end
  end

  test "fails closed without root keys", %{conn: conn} = context do
    stub(Environment, :kura_volume_root_keys, fn -> [] end)
    reject(&Client.create_bound_token_review/3)

    assert conn |> request(context) |> json_response(503) == %{"error" => "unavailable"}
  end

  test "answers 503 when the Kubernetes API fails", %{conn: conn} = context do
    stub(Client, :get_persistent_volume, fn _name, _opts -> {:error, "Kubernetes API GET returned 500"} end)
    assert conn |> request(context) |> json_response(503) == %{"error" => "unavailable"}
  end

  test "rate limits callers", %{conn: conn} = context do
    stub(RateLimit, :hit, fn "kura_volume_keys:ip:" <> _ip, _opts -> {:deny, 1_000} end)
    reject(&Client.create_bound_token_review/3)

    assert conn |> request(context) |> json_response(429) == %{"error" => "rate_limited"}
  end

  defp request(conn, context, extra \\ %{}, token \\ "node-token") do
    conn =
      if token, do: put_req_header(conn, "authorization", "Bearer #{token}"), else: conn

    post(
      conn,
      ~p"/_internal/kura/volume-keys",
      Map.merge(%{"volume_id" => @volume_id, "public_key" => Base.encode64(context.client_public)}, extra)
    )
  end

  defp open(response, %{client_public: client_public, client_private: client_private}) do
    server_public = Base.decode64!(response["ephemeral_public_key"])
    nonce = Base.decode64!(response["nonce"])
    sealed = Base.decode64!(response["ciphertext"])

    shared = :crypto.compute_key(:ecdh, server_public, client_private, :x25519)
    key = HKDF.derive(shared, server_public <> client_public, "kura-volume-key-transport/v1", 32)
    <<ciphertext::binary-size(32), tag::binary-size(16)>> = sealed

    passphrase = :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ciphertext, @volume_id, tag, false)
    assert byte_size(passphrase) == 32
    passphrase
  end

  defp persistent_volume do
    %{
      "metadata" => %{"name" => @volume_id},
      "spec" => %{
        "csi" => %{"driver" => "kura-volumes.tuist.dev", "volumeHandle" => @volume_id},
        "nodeAffinity" => %{"required" => %{"nodeSelectorTerms" => [node_term(@node)]}},
        "claimRef" => %{"namespace" => "kura", "name" => "data-kura-0", "uid" => @claim_uid}
      }
    }
  end

  defp pinned_to(values) do
    put_in(persistent_volume(), ["spec", "nodeAffinity", "required", "nodeSelectorTerms"], [
      %{
        "matchExpressions" => [
          %{"key" => "topology.kura-volumes.tuist.dev/node", "operator" => "In", "values" => values}
        ]
      }
    ])
  end

  defp node_term(node) do
    %{
      "matchExpressions" => [
        %{"key" => "topology.kura-volumes.tuist.dev/node", "operator" => "In", "values" => [node]}
      ]
    }
  end

  defp claim(instance) do
    %{
      "metadata" => %{
        "name" => "data-kura-0",
        "namespace" => "kura",
        "uid" => @claim_uid,
        "labels" => %{"app.kubernetes.io/instance" => instance}
      },
      "spec" => %{"volumeName" => @volume_id}
    }
  end
end
