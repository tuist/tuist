defmodule Atlas.Repo.Migrations.ConsolidateEmailAudiences do
  use Ecto.Migration

  def up do
    # A contact can belong to both enterprise lists. Merge the status onto the
    # target first so deleting the duplicate membership cannot downgrade an
    # active subscription.
    execute("""
    UPDATE gtm_audience_memberships AS target_membership
    SET
      status = CASE
        WHEN target_membership.status = 'subscribed' OR source_membership.status = 'subscribed'
          THEN 'subscribed'
        WHEN target_membership.status = 'pending' OR source_membership.status = 'pending'
          THEN 'pending'
        ELSE 'unsubscribed'
      END,
      unsubscribed_at = CASE
        WHEN target_membership.status = 'subscribed' OR source_membership.status = 'subscribed'
          THEN NULL
        ELSE COALESCE(target_membership.unsubscribed_at, source_membership.unsubscribed_at)
      END,
      updated_at = GREATEST(target_membership.updated_at, source_membership.updated_at)
    FROM
      gtm_audience_memberships AS source_membership,
      gtm_audiences AS target_audience,
      gtm_audiences AS source_audience
    WHERE target_audience.slug = 'enterprise-incident-emails'
      AND source_audience.slug = 'enterprise-security-incident-emails'
      AND target_membership.audience_id = target_audience.id
      AND source_membership.audience_id = source_audience.id
      AND source_membership.subscriber_id = target_membership.subscriber_id
    """)

    execute("""
    DELETE FROM gtm_audience_memberships AS source_membership
    USING gtm_audiences AS target_audience, gtm_audiences AS source_audience
    WHERE target_audience.slug = 'enterprise-incident-emails'
      AND source_audience.slug = 'enterprise-security-incident-emails'
      AND source_membership.audience_id = source_audience.id
      AND EXISTS (
        SELECT 1
        FROM gtm_audience_memberships AS target_membership
        WHERE target_membership.audience_id = target_audience.id
          AND target_membership.subscriber_id = source_membership.subscriber_id
      )
    """)

    execute("""
    UPDATE gtm_audience_memberships AS membership
    SET audience_id = target_audience.id
    FROM gtm_audiences AS target_audience, gtm_audiences AS source_audience
    WHERE target_audience.slug = 'enterprise-incident-emails'
      AND source_audience.slug = 'enterprise-security-incident-emails'
      AND membership.audience_id = source_audience.id
    """)

    execute("DELETE FROM gtm_audiences WHERE slug = 'enterprise-security-incident-emails'")
    execute("DELETE FROM gtm_audiences WHERE slug = 'tuist-qa-interested-people'")

    execute("""
    UPDATE gtm_audiences
    SET
      name = 'Enterprise incident contacts',
      slug = 'enterprise-incident-contacts',
      description = 'Operational and security contacts for enterprise incident communication.',
      updated_at = NOW()
    WHERE slug = 'enterprise-incident-emails'
    """)

    execute("""
    UPDATE gtm_audiences
    SET
      name = 'Email Digest',
      slug = 'email-digest',
      description = 'Subscribers who opted in to receive the email digest.',
      updated_at = NOW()
    WHERE slug = 'tuist-digest'
    """)

    execute("""
    UPDATE gtm_audiences
    SET
      name = 'Users',
      slug = 'users',
      description = 'Product users eligible for the welcome email.',
      updated_at = NOW()
    WHERE slug = 'posthog-signups'
    """)
  end

  def down do
    raise "consolidating email audiences cannot be reversed without losing membership history"
  end
end
