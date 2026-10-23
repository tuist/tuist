defmodule Tuist.Repo.Migrations.IndexOauthTokenRefreshLookupTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Ecto.Adapters.SQL
  alias Tuist.Repo

  test "refresh-token lookup has a valid non-unique partial btree index" do
    assert %{rows: [[true, true, false, "btree", definition, predicate]]} =
             SQL.query!(Repo, """
             SELECT i.indisvalid, i.indisready, i.indisunique, a.amname,
                    pg_get_indexdef(i.indexrelid), pg_get_expr(i.indpred, i.indrelid)
             FROM pg_index i
             JOIN pg_class c ON c.oid = i.indexrelid
             JOIN pg_am a ON a.oid = c.relam
             WHERE i.indrelid = 'oauth_tokens'::regclass
               AND c.relname = 'oauth_tokens_refresh_token_index'
             """)

    assert definition =~ "USING btree (refresh_token)"
    assert predicate == "(refresh_token IS NOT NULL)"
  end
end
