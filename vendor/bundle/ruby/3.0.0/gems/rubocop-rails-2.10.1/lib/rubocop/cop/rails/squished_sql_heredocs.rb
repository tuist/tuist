# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      #
      # Checks SQL heredocs to use `.squish`.
      # Some SQL syntax (e.g. PostgreSQL comments and functions) requires newlines
      # to be preserved in order to work, thus auto-correction for this cop is not safe.
      #
      # @example
      #   # bad
      #   <<-SQL
      #     SELECT * FROM posts;
      #   SQL
      #
      #   <<-SQL
      #     SELECT * FROM posts
      #       WHERE id = 1
      #   SQL
      #
      #   execute(<<~SQL, "Post Load")
      #     SELECT * FROM posts
      #       WHERE post_id = 1
      #   SQL
      #
      #   # good
      #   <<-SQL.squish
      #     SELECT * FROM posts;
      #   SQL
      #
      #   <<~SQL.squish
      #     SELECT * FROM table
      #       WHERE id = 1
      #   SQL
      #
      #   execute(<<~SQL.squish, "Post Load")
      #     SELECT * FROM posts
      #       WHERE post_id = 1
      #   SQL
      #
      class SquishedSQLHeredocs < Base
        include Heredoc
        extend AutoCorrector

        SQL = 'SQL'
        SQUISH = '.squish'
        MSG = 'Use `%<expect>s` instead of `%<current>s`.'

        def on_heredoc(node)
          return unless offense_detected?(node)

          add_offense(node) do |corrector|
            corrector.insert_after(node, SQUISH)
          end
        end

        private

        def offense_detected?(node)
          sql_heredoc?(node) && !using_squish?(node)
        end

        def sql_heredoc?(node)
          delimiter_string(node) == SQL
        end

        def using_squish?(node)
          node.parent&.send_type? && node.parent&.method?(:squish)
        end

        def message(node)
          format(
            MSG,
            expect: "#{node.source}#{SQUISH}",
            current: node.source
          )
        end
      end
    end
  end
end
