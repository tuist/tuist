module Cucumber
  module MultilineArgument
    class DataTable
      class DiffMatrices #:nodoc:
        attr_accessor :cell_matrix, :other_table_cell_matrix, :options

        def initialize(cell_matrix, other_table_cell_matrix, options)
          @cell_matrix = cell_matrix
          @other_table_cell_matrix = other_table_cell_matrix
          @options = options
        end

        def call
          prepare_diff
          perform_diff
          fill_in_missing_values
          raise_error if should_raise?
        end

        private

        attr_reader :row_indices, :original_width, :original_header, :padded_width, :missing_row_pos, :insert_row_pos

        def prepare_diff
          @original_width = cell_matrix[0].length
          @original_header = other_table_cell_matrix[0]
          pad_and_match
          @padded_width = cell_matrix[0].length
          @row_indices = Array.new(other_table_cell_matrix.length) { |n| n }
        end

        # Pads two cell matrices to same column width and matches columns according to header value.
        def pad_and_match
          cols = cell_matrix.transpose
          unmatched_cols = other_table_cell_matrix.transpose

          header_values = cols.map(&:first)
          matched_cols = []

          header_values.each_with_index do |v, i|
            mapped_index = unmatched_cols.index { |unmapped_col| unmapped_col.first == v }
            if mapped_index
              matched_cols << unmatched_cols.delete_at(mapped_index)
            else
              mark_as_missing(cols[i])
              empty_col = ensure_2d(other_table_cell_matrix).collect { SurplusCell.new(nil, self, -1) }
              empty_col.first.value = v
              matched_cols << empty_col
            end
          end

          unmatched_cols.each do
            empty_col = cell_matrix.collect { SurplusCell.new(nil, self, -1) }
            cols << empty_col
          end

          self.cell_matrix = ensure_2d(cols.transpose)
          self.other_table_cell_matrix = ensure_2d((matched_cols + unmatched_cols).transpose)
        end

        def mark_as_missing(col)
          col.each do |cell|
            cell.status = :undefined
          end
        end

        def ensure_2d(array)
          array[0].is_a?(Array) ? array : [array]
        end

        def perform_diff
          inserted    = 0
          missing     = 0
          last_change = nil

          changes.each do |change|
            if change.action == '-'
              @missing_row_pos = change.position + inserted
              cell_matrix[missing_row_pos].each { |cell| cell.status = :undefined }
              row_indices.insert(missing_row_pos, nil)
              missing += 1
            else # '+'
              @insert_row_pos = change.position + missing
              inserted_row = change.element
              inserted_row.each { |cell| cell.status = :comment }
              cell_matrix.insert(insert_row_pos, inserted_row)
              row_indices[insert_row_pos] = nil
              inspect_rows(cell_matrix[missing_row_pos], inserted_row) if last_change == '-'
              inserted += 1
            end
            last_change = change.action
          end
        end

        def changes
          require 'diff/lcs'
          diffable_cell_matrix = cell_matrix.dup.extend(::Diff::LCS)
          diffable_cell_matrix.diff(other_table_cell_matrix).flatten(1)
        end

        def inspect_rows(missing_row, inserted_row)
          missing_row.each_with_index do |missing_cell, col|
            inserted_cell = inserted_row[col]
            if missing_cell.value != inserted_cell.value && missing_cell.value.to_s == inserted_cell.value.to_s
              missing_cell.inspect!
              inserted_cell.inspect!
            end
          end
        end

        def fill_in_missing_values
          other_table_cell_matrix.each_with_index do |other_row, i|
            row_index = row_indices.index(i)
            row = cell_matrix[row_index] if row_index
            next unless row
            (original_width..padded_width).each do |col_index|
              surplus_cell = other_row[col_index]
              row[col_index].value = surplus_cell.value if row[col_index]
            end
          end
        end

        def missing_col
          cell_matrix[0].find { |cell| cell.status == :undefined }
        end

        def surplus_col
          padded_width > original_width
        end

        def misplaced_col
          cell_matrix[0] != original_header
        end

        def raise_error
          table = DataTable.from([[]])
          table.instance_variable_set :@cell_matrix, cell_matrix
          raise Different, table if should_raise?
        end

        def should_raise?
          [
            missing_row_pos && options.fetch(:missing_row, true),
            insert_row_pos  && options.fetch(:surplus_row, true),
            missing_col     && options.fetch(:missing_col, true),
            surplus_col     && options.fetch(:surplus_col, false),
            misplaced_col   && options.fetch(:misplaced_col, false)
          ].any?
        end
      end
      private_constant :DiffMatrices
    end
  end
end
