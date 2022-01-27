# frozen_string_literal: true
require 'cucumber/core/test/doc_string'
require 'unindent'

module Cucumber
  module Core
    module Test
      describe DocString do
        let(:doc_string) { DocString.new(content, content_type) }

        describe "#data_table?" do
          let(:doc_string) { DocString.new("test", "text/plain" ) }

          it "returns false" do
            expect(doc_string).not_to be_data_table
          end
        end

        describe "#doc_string" do
          let(:doc_string) { DocString.new("test", "text/plain" ) }

          it "returns true" do
            expect(doc_string).to be_doc_string
          end
        end

        context '#map' do
          let(:content) { 'original content' }
          let(:content_type) { double }

          it 'yields with the content' do
            expect { |b| doc_string.map(&b) }.to yield_with_args(content)
          end

          it 'returns a new docstring with new content' do
            expect( doc_string.map { 'foo' }.content ).to eq 'foo'
          end

          it 'raises an error if no block is given' do
            expect { doc_string.map }.to raise_error ArgumentError
          end
        end

        context 'equality' do
          let(:content) { 'foo' }
          let(:content_type) { 'text/plain' }

          it 'is equal to another DocString with the same content and content_type' do
            expect( doc_string ).to eq DocString.new(content, content_type)
          end

          it 'is not equal to another DocString with different content' do
            expect( doc_string ).not_to eq DocString.new('bar', content_type)
          end

          it 'is not equal to another DocString with different content_type' do
            expect( doc_string ).not_to eq DocString.new(content, 'text/html')
          end

          it 'is equal to a string with the same content' do
            expect( doc_string ).to eq 'foo'
          end

          it 'returns false when compared with something odd' do
            expect( doc_string ).not_to eq 5
          end
        end

        context 'quacking like a String' do
          let(:content) { String.new('content') }
          let(:content_type) { 'text/plain' }

          it 'delegates #encoding to the content string' do
            content.force_encoding('us-ascii')
            expect( doc_string.encoding ).to eq Encoding.find('US-ASCII')
          end

          it 'allows implicit conversion to a String' do
            expect( 'expected content' ).to include(doc_string)
          end

          it 'allows explicit conversion to a String' do
            expect( doc_string.to_s ).to eq 'content'
          end

          it 'delegates #gsub to the content string' do
            expect( doc_string.gsub(/n/, '_') ).to eq 'co_te_t'
          end

          it 'delegates #split to the content string' do
            expect(doc_string.split('n')).to eq ['co', 'te', 't']
          end
        end
      end

      context "inspect" do
        let(:content_type) { 'text/plain' }

        it "provides a useful inspect method" do
          doc_string = DocString.new("some text", content_type)
          expect(doc_string.inspect).to eq <<-END.chomp.unindent
          #<Cucumber::Core::Test::DocString
            """text/plain
            some text
            """>
          END
        end
      end
    end
  end
end
