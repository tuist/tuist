defmodule Atlas.Insurance.Policies do
  @moduledoc """
  Public context for insurance policies, dated membership, and claims.

  Membership uses half-open intervals `[covered_from, covered_to)`. Opening
  a member on an asset that already has an open member on the same policy
  fails via a partial unique index. Different policies can cover the same
  asset concurrently.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Documents.Document
  alias Atlas.Insurance.Claim
  alias Atlas.Insurance.ClaimAsset
  alias Atlas.Insurance.ClaimDocument
  alias Atlas.Insurance.Policy
  alias Atlas.Insurance.PolicyDocument
  alias Atlas.Insurance.PolicyMember
  alias Atlas.Repo

  ## ------------------------------------------------------------------
  ## Reads
  ## ------------------------------------------------------------------

  def list(params \\ %{}) do
    Policy
    |> order_by([p], desc: p.inserted_at, asc: p.id)
    |> Flop.run(struct(Flop, params), for: Policy)
  end

  def get(id) when is_binary(id) do
    case Atlas.UUIDv7.cast(id) do
      {:ok, id} -> Repo.get(Policy, id)
      :error -> nil
    end
  end

  def get(_id), do: nil

  def get!(id) when is_binary(id), do: Repo.get!(Policy, id)

  def list_members(%Policy{id: id}) do
    PolicyMember
    |> where([m], m.policy_id == ^id)
    |> preload(:asset)
    |> order_by([m], desc: m.covered_from, asc: m.id)
    |> Repo.all()
  end

  def list_open_members(%Policy{id: id}) do
    PolicyMember
    |> where([m], m.policy_id == ^id and is_nil(m.covered_to))
    |> preload(:asset)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  def list_claims(%Policy{id: id}) do
    Claim
    |> where([c], c.policy_id == ^id)
    |> order_by([c], desc: c.incident_on, desc: c.id)
    |> Repo.all()
  end

  def get_claim(id) when is_binary(id) do
    case Atlas.UUIDv7.cast(id) do
      {:ok, id} -> Repo.get(Claim, id) |> maybe_preload_claim()
      :error -> nil
    end
  end

  def get_claim(_id), do: nil

  ## ------------------------------------------------------------------
  ## Changesets
  ## ------------------------------------------------------------------

  def change(attrs \\ %{}), do: Policy.create_changeset(%Policy{}, attrs)
  def change(%Policy{} = policy, attrs), do: Policy.metadata_changeset(policy, attrs)

  ## ------------------------------------------------------------------
  ## Policy CRUD + lifecycle
  ## ------------------------------------------------------------------

  def create(attrs) when is_map(attrs) do
    %Policy{}
    |> Policy.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, policy} = ok ->
        audit_policy("insurance.policy_created", policy, %{
          "provider" => policy.provider,
          "product" => policy.product,
          "sum_insured" => decimal_string(policy.sum_insured),
          "currency" => policy.currency
        })

        ok

      other ->
        other
    end
  end

  def edit_metadata(%Policy{} = policy, attrs) when is_map(attrs) do
    policy
    |> Policy.metadata_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} = ok ->
        audit_policy("insurance.policy_edited", updated, %{
          "changed_fields" =>
            attrs
            |> Enum.map(fn {k, _v} -> to_string(k) end)
            |> Enum.sort()
        })

        ok

      other ->
        other
    end
  end

  def delete(%Policy{} = policy) do
    if Repo.exists?(from(m in PolicyMember, where: m.policy_id == ^policy.id)) or
         Repo.exists?(from(c in Claim, where: c.policy_id == ^policy.id)) do
      changeset =
        policy
        |> Policy.metadata_changeset(%{})
        |> Ecto.Changeset.add_error(:base, "has members or claims; expire it instead")

      {:error, changeset}
    else
      case Repo.delete(policy) do
        {:ok, deleted} = ok ->
          audit_policy("insurance.policy_deleted", deleted, %{"provider" => deleted.provider})
          ok

        other ->
          other
      end
    end
  end

  def activate(policy, opts \\ [])

  def activate(%Policy{status: status} = policy, opts) when status in ["quoted", "active"] do
    starts_on = Keyword.get(opts, :starts_on)

    attrs = %{status: "active"}

    Repo.transaction(fn ->
      changeset = Policy.status_changeset(policy, attrs)

      changeset =
        if starts_on && is_nil(policy.starts_on) do
          Ecto.Changeset.change(changeset, %{starts_on: starts_on})
        else
          changeset
        end

      case Repo.update(changeset) do
        {:ok, updated} -> updated
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, updated} ->
        audit_policy("insurance.policy_activated", updated, %{"starts_on" => date_string(updated.starts_on)})
        {:ok, updated}

      other ->
        other
    end
  end

  def activate(_policy, _opts), do: {:error, :invalid_state_transition}

  def expire(%Policy{} = policy, opts \\ []) do
    ends_on = Keyword.get(opts, :ends_on, Date.utc_today())

    attrs = %{status: "expired"}

    Repo.transaction(fn ->
      changeset =
        policy
        |> Policy.status_changeset(attrs)
        |> Ecto.Changeset.change(%{ends_on: ends_on})

      with {:ok, updated} <- Repo.update(changeset),
           :ok <- close_open_members(updated, ends_on) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, updated} ->
        audit_policy("insurance.policy_expired", updated, %{"ends_on" => date_string(ends_on)})
        {:ok, updated}

      other ->
        other
    end
  end

  def cancel(%Policy{} = policy, opts \\ []) do
    ends_on = Keyword.get(opts, :ends_on, Date.utc_today())

    Repo.transaction(fn ->
      changeset =
        policy
        |> Policy.status_changeset(%{status: "cancelled"})
        |> Ecto.Changeset.change(%{ends_on: ends_on})

      with {:ok, updated} <- Repo.update(changeset),
           :ok <- close_open_members(updated, ends_on) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, updated} ->
        audit_policy("insurance.policy_cancelled", updated, %{"ends_on" => date_string(ends_on)})
        {:ok, updated}

      other ->
        other
    end
  end

  ## ------------------------------------------------------------------
  ## Members
  ## ------------------------------------------------------------------

  def add_member(%Policy{} = policy, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.put_new(:policy_id, policy.id)
      |> Map.put_new(:covered_from, Date.utc_today())

    %PolicyMember{}
    |> PolicyMember.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, member} = ok ->
        audit_policy("insurance.member_added", policy, %{
          "asset_id" => member.asset_id,
          "declared_value" => decimal_string(member.declared_value),
          "covered_from" => date_string(member.covered_from)
        })

        ok

      other ->
        other
    end
  end

  def close_member(member, opts \\ [])

  def close_member(%PolicyMember{covered_to: nil} = member, opts) do
    covered_to = Keyword.get(opts, :covered_to, Date.utc_today())

    member
    |> PolicyMember.close_changeset(%{covered_to: covered_to})
    |> Repo.update()
    |> case do
      {:ok, updated} = ok ->
        audit_policy_id("insurance.member_closed", updated.policy_id, %{
          "asset_id" => updated.asset_id,
          "covered_to" => date_string(covered_to)
        })

        ok

      other ->
        other
    end
  end

  def close_member(_member, _opts), do: {:error, :already_closed}

  def edit_member(%PolicyMember{} = member, attrs) when is_map(attrs) do
    member
    |> PolicyMember.update_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} = ok ->
        audit_policy_id("insurance.member_edited", updated.policy_id, %{
          "asset_id" => updated.asset_id,
          "declared_value" => decimal_string(updated.declared_value)
        })

        ok

      other ->
        other
    end
  end

  def get_member(id) when is_binary(id) do
    case Atlas.UUIDv7.cast(id) do
      {:ok, id} -> Repo.get(PolicyMember, id)
      :error -> nil
    end
  end

  def get_member(_id), do: nil

  defp close_open_members(%Policy{id: id}, %Date{} = ends_on) do
    from(m in PolicyMember, where: m.policy_id == ^id and is_nil(m.covered_to))
    |> Repo.update_all(set: [covered_to: ends_on, updated_at: DateTime.utc_now(:second)])

    :ok
  end

  ## ------------------------------------------------------------------
  ## Claims
  ## ------------------------------------------------------------------

  def create_claim(%Policy{} = policy, attrs) when is_map(attrs) do
    attrs = Map.put_new(attrs, :policy_id, policy.id)

    %Claim{}
    |> Claim.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, claim} = ok ->
        audit_policy("insurance.claim_created", policy, %{
          "claim_id" => claim.id,
          "incident_on" => date_string(claim.incident_on),
          "incident_type" => claim.incident_type,
          "status" => claim.status
        })

        ok

      other ->
        other
    end
  end

  def update_claim(%Claim{} = claim, attrs) when is_map(attrs) do
    claim
    |> Claim.update_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} = ok ->
        audit_policy_id("insurance.claim_updated", updated.policy_id, %{
          "claim_id" => updated.id,
          "status" => updated.status
        })

        ok

      other ->
        other
    end
  end

  def link_asset_to_claim(%Claim{} = claim, asset_id, attrs \\ %{}) when is_binary(asset_id) do
    attrs =
      attrs
      |> Map.put(:claim_id, claim.id)
      |> Map.put(:asset_id, asset_id)

    %ClaimAsset{}
    |> ClaimAsset.create_changeset(attrs)
    |> Repo.insert()
  end

  def unlink_asset_from_claim(%Claim{id: claim_id}, asset_id) when is_binary(asset_id) do
    case Repo.get_by(ClaimAsset, claim_id: claim_id, asset_id: asset_id) do
      nil -> {:error, :not_found}
      link -> Repo.delete(link)
    end
  end

  def list_claim_assets(%Claim{id: id}) do
    ClaimAsset
    |> where([l], l.claim_id == ^id)
    |> preload(:asset)
    |> Repo.all()
  end

  defp maybe_preload_claim(nil), do: nil
  defp maybe_preload_claim(%Claim{} = claim), do: Repo.preload(claim, [:policy, assets: :asset])

  ## ------------------------------------------------------------------
  ## Documents (policy and claim)
  ## ------------------------------------------------------------------

  def attach_document_to_policy(%Policy{} = policy, document_id, kind, opts \\ []) when is_binary(document_id) do
    case Repo.get(Document, document_id) do
      %Document{} ->
        %PolicyDocument{}
        |> PolicyDocument.create_changeset(%{
          policy_id: policy.id,
          document_id: document_id,
          kind: to_string(kind),
          notes: Keyword.get(opts, :notes)
        })
        |> Repo.insert()
        |> case do
          {:ok, link} = ok ->
            audit_policy("insurance.policy_document_attached", policy, %{
              "document_id" => document_id,
              "kind" => link.kind
            })

            ok

          other ->
            other
        end

      nil ->
        {:error, :document_not_found}
    end
  end

  def detach_document_from_policy(link_id) when is_binary(link_id) do
    case Repo.get(PolicyDocument, link_id) do
      nil ->
        {:error, :not_found}

      link ->
        case Repo.delete(link) do
          {:ok, deleted} = ok ->
            audit_policy_id("insurance.policy_document_detached", deleted.policy_id, %{
              "document_id" => deleted.document_id,
              "kind" => deleted.kind
            })

            ok

          other ->
            other
        end
    end
  end

  def list_policy_documents(%Policy{id: id}) do
    PolicyDocument
    |> where([l], l.policy_id == ^id)
    |> preload(:document)
    |> order_by([l],
      asc: fragment("array_position(ARRAY['policy','quote','avb','renewal','endorsement','other']::text[], ?)", l.kind),
      desc: l.inserted_at
    )
    |> Repo.all()
  end

  def attach_document_to_claim(%Claim{} = claim, document_id, kind, opts \\ []) when is_binary(document_id) do
    case Repo.get(Document, document_id) do
      %Document{} ->
        %ClaimDocument{}
        |> ClaimDocument.create_changeset(%{
          claim_id: claim.id,
          document_id: document_id,
          kind: to_string(kind),
          notes: Keyword.get(opts, :notes)
        })
        |> Repo.insert()
        |> case do
          {:ok, link} = ok ->
            audit_policy_id("insurance.claim_document_attached", claim.policy_id, %{
              "claim_id" => claim.id,
              "document_id" => document_id,
              "kind" => link.kind
            })

            ok

          other ->
            other
        end

      nil ->
        {:error, :document_not_found}
    end
  end

  def detach_document_from_claim(link_id) when is_binary(link_id) do
    case Repo.get(ClaimDocument, link_id) do
      nil ->
        {:error, :not_found}

      link ->
        case Repo.delete(link) do
          {:ok, deleted} = ok ->
            audit_policy_id("insurance.claim_document_detached", deleted.claim_id, %{
              "document_id" => deleted.document_id,
              "kind" => deleted.kind
            })

            ok

          other ->
            other
        end
    end
  end

  def list_claim_documents(%Claim{id: id}) do
    ClaimDocument
    |> where([l], l.claim_id == ^id)
    |> preload(:document)
    |> order_by([l], desc: l.inserted_at)
    |> Repo.all()
  end

  ## ------------------------------------------------------------------
  ## Audit helpers
  ## ------------------------------------------------------------------

  defp audit_policy(action, %Policy{} = policy, metadata) do
    Audit.record(action, %{
      target_type: "insurance_policy",
      target_id: policy.id,
      target_label: "#{policy.provider} · #{policy.product}",
      metadata: metadata
    })
  end

  defp audit_policy_id(action, policy_id, metadata) do
    Audit.record(action, %{
      target_type: "insurance_policy",
      target_id: policy_id,
      target_label: policy_id,
      metadata: metadata
    })
  end

  defp decimal_string(nil), do: nil
  defp decimal_string(%Decimal{} = d), do: Decimal.to_string(d, :normal)

  defp date_string(nil), do: nil
  defp date_string(%Date{} = d), do: Date.to_iso8601(d)
end
