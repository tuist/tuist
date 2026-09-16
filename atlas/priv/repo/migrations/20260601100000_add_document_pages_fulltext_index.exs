defmodule Atlas.Repo.Migrations.AddDocumentPagesFulltextIndex do
  use Ecto.Migration

  # GIN index over the English full-text vector of page content. This powers the
  # lexical half of hybrid search and uses only built-in Postgres full-text
  # search, so it needs no extension (unlike pg_trgm or pgvector).
  def up do
    execute("""
    CREATE INDEX document_pages_content_fts_index
    ON document_pages
    USING gin (to_tsvector('english', content))
    """)
  end

  def down do
    execute("DROP INDEX document_pages_content_fts_index")
  end
end
