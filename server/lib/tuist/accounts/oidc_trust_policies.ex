defmodule Tuist.Accounts.OIDCTrustPolicies do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Changeset
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.OIDCTrustPolicy
  alias Tuist.Projects.Project
  alias Tuist.Repo

  def list(%Account{id: account_id}) do
    projects = from p in Project, where: p.account_id == ^account_id, order_by: p.name

    Repo.all(
      from p in OIDCTrustPolicy, where: p.account_id == ^account_id, order_by: p.id, preload: [projects: ^projects]
    )
  end

  def create(%Account{id: account_id}, attrs) do
    changeset = OIDCTrustPolicy.changeset(%OIDCTrustPolicy{account_id: account_id}, attrs)

    if changeset.valid? do
      Repo.transaction(fn ->
        Repo.one!(from a in Account, where: a.id == ^account_id, lock: "FOR UPDATE")
        count = Repo.aggregate(from(p in OIDCTrustPolicy, where: p.account_id == ^account_id), :count)

        if count >= 20 do
          Repo.rollback(Changeset.add_error(changeset, :name, "cannot exceed 20 trust policies per account"))
        end

        project_ids = changeset |> Changeset.get_field(:project_ids) |> Enum.uniq()

        projects =
          Repo.all(
            from p in Project,
              where: p.id in ^project_ids and p.account_id == ^account_id,
              order_by: p.id,
              lock: "FOR SHARE"
          )

        if length(projects) != length(project_ids) do
          Repo.rollback(Changeset.add_error(changeset, :project_ids, "must select projects belonging to this account"))
        end

        changeset = Changeset.put_assoc(changeset, :projects, projects)

        case Repo.insert(changeset) do
          {:ok, policy} -> policy
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    else
      {:error, changeset}
    end
  end

  def delete(%Account{id: account_id}, policy_id) do
    case Repo.get_by(OIDCTrustPolicy, id: policy_id, account_id: account_id) do
      nil -> {:error, :not_found}
      policy -> Repo.delete(policy)
    end
  end

  # Unsigned hints only bound verification work; they never grant access.
  def candidates(issuer, account_handle, claims) do
    scalar_claims = Map.filter(claims, fn {_, value} -> is_binary(value) or is_integer(value) or is_boolean(value) end)
    audiences = List.wrap(claims["aud"])
    audiences = if Enum.all?(audiences, &is_binary/1), do: audiences, else: []

    Repo.all(
      from policy in OIDCTrustPolicy,
        join: account in assoc(policy, :account),
        join: project in assoc(policy, :projects),
        where: policy.issuer == ^issuer,
        where: account.name == ^account_handle,
        where: project.account_id == account.id,
        where: policy.audience in ^audiences,
        where: fragment("? @> ?", type(^scalar_claims, :map), policy.claims),
        distinct: true,
        order_by: policy.id,
        limit: 21
    )
  end
end
