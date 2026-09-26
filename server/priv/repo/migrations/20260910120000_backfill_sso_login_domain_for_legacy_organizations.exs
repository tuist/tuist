defmodule Tuist.Repo.Migrations.BackfillSsoLoginDomainForLegacyOrganizations do
  use Ecto.Migration

  import Ecto.Query

  @token_length 32
  @dominant_share 0.9

  def up, do: backfill_login_domains!(repo())

  def down, do: :ok

  # Inert until `sso_login_domain_verified_at` is set, which only DNS verification does.
  def backfill_login_domains!(repo) do
    for {organization_id, domain} <- dominant_member_domains(repo) do
      repo.update_all(
        from(organization in "organizations",
          where: organization.id == ^organization_id,
          where: is_nil(organization.sso_login_domain)
        ),
        set: [
          sso_login_domain: domain,
          sso_login_domain_verification_token: verification_token()
        ]
      )
    end

    :ok
  end

  defp dominant_member_domains(repo) do
    from(role in "roles",
      join: user_role in "users_roles",
      on: user_role.role_id == role.id,
      join: user in "users",
      on: user.id == user_role.user_id,
      join: organization in "organizations",
      on: organization.id == role.resource_id,
      where: role.resource_type == "Organization",
      where: organization.sso_legacy_email_domain_fallback == true,
      where: is_nil(organization.sso_login_domain),
      group_by: [role.resource_id, fragment("lower(split_part(?::text, '@', 2))", user.email)],
      select:
        {role.resource_id, fragment("lower(split_part(?::text, '@', 2))", user.email),
         count(user_role.user_id, :distinct)}
    )
    |> repo.all()
    |> Enum.reject(fn {_organization_id, domain, _members} -> domain in [nil, ""] end)
    |> Enum.group_by(fn {organization_id, _domain, _members} -> organization_id end)
    |> Enum.flat_map(&dominant_domain/1)
  end

  defp dominant_domain({organization_id, member_counts}) do
    total = member_counts |> Enum.map(&elem(&1, 2)) |> Enum.sum()
    {_organization_id, domain, members} = Enum.max_by(member_counts, &elem(&1, 2))

    if members >= @dominant_share * total, do: [{organization_id, domain}], else: []
  end

  defp verification_token do
    @token_length
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
    |> binary_part(0, @token_length)
  end
end
