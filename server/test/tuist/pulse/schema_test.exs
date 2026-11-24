defmodule Tuist.Pulse.SchemaTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo

  @tables ~w(pulse_symptoms pulse_symptom_revisions pulse_symptom_acks pulse_symptom_mutes pulse_symptom_outcomes
             pulse_investigations pulse_briefs pulse_brief_steps)

  test "every foreign key of the Pulse tables leads an index" do
    # Without one, deleting an account, user or symptom scans the table.
    %{rows: rows} =
      Repo.query!(
        """
        SELECT c.conrelid::regclass::text, a.attname
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
        WHERE c.contype = 'f' AND cardinality(c.conkey) = 1 AND c.conrelid::regclass::text = ANY($1)
          AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = c.conrelid AND i.indkey[0] = c.conkey[1])
        ORDER BY 1, 2
        """,
        [@tables]
      )

    assert rows == []
  end
end
