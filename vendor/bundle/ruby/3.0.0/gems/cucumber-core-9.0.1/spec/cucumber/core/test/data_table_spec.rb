# encoding: utf-8
# frozen_string_literal: true
require 'cucumber/core/test/data_table'

module Cucumber
  module Core
    module Test
      describe DataTable do
        before do
          @table = DataTable.new([
            %w{one four seven},
            %w{4444 55555 666666}
          ])
        end

        describe "equality" do
          it "is equal to another table with the same data" do
            expect( DataTable.new([[1, 2], [3, 4]]) ).to eq DataTable.new([[1, 2], [3, 4]])
          end

          it "is not equal to another table with different data" do
            expect( DataTable.new([[1, 2], [3, 4]]) ).not_to eq DataTable.new([[1, 2]])
          end

          it "is not equal to a non table" do
            expect( DataTable.new([[1, 2], [3, 4]]) ).not_to eq Object.new
          end
        end

        describe "#data_table?" do
          let(:table) { DataTable.new([[1, 2], [3, 4]]) }

          it "returns true" do
            expect(table).to be_data_table
          end
        end

        describe "#doc_string" do
          let(:table) { DataTable.new([[1, 2], [3, 4]]) }

          it "returns false" do
            expect(table).not_to be_doc_string
          end
        end

        describe "#map" do
          let(:table) { DataTable.new([ %w{foo bar}, %w{1 2} ]) }

          it 'yields the contents of each cell to the block' do

            expect { |b| table.map(&b) }.to yield_successive_args('foo', 'bar', '1', '2')
          end

          it 'returns a new table with the cells modified by the block' do
            expect( table.map { |cell| "*#{cell}*" } ).to eq DataTable.new([%w{*foo* *bar*}, %w{*1* *2*}])
          end
        end

        describe "#transpose" do
          before(:each) do
            @table = DataTable.new([
              %w{one 1111},
              %w{two 22222}
            ])
          end

          it "should transpose the table" do
            transposed = DataTable.new([
              %w{one two},
              %w{1111 22222}
            ])
            expect( @table.transpose ).to eq( transposed )
          end
        end

      end
    end
  end
end
