# frozen_string_literal: true
require 'cucumber/core/test/location'

module Cucumber::Core::Test
  RSpec::Matchers.define :be_included_in do |expected|
    match do |actual|
      expected.include? actual
    end
  end

  describe Location do
    let(:line) { 12 }
    let(:file) { "foo.feature" }

    describe "equality" do
      it "is equal to another Location on the same line of the same file" do
        one_location = Location.new(file, line)
        another_location = Location.new(file, line)
        expect( one_location ).to eq another_location
      end

      it "is not equal to a wild card of the same file" do
        expect( Location.new(file, line) ).not_to eq Location.new(file)
      end

      context "collections of locations" do
        it "behave as expected with uniq" do
          unique_collection = [Location.new(file, line), Location.new(file, line)].uniq
          expect( unique_collection ).to eq [Location.new(file, line)]
        end
      end
    end

    describe "to_s" do
      it "is file:line for a precise location" do
        expect( Location.new("foo.feature", 12).to_s ).to eq "foo.feature:12"
      end

      it "is file for a wildcard location" do
        expect( Location.new("foo.feature").to_s ).to eq "foo.feature"
      end

      it "is file:first_line..last_line for a ranged location" do
        expect( Location.new("foo.feature", 13..19).to_s ).to eq "foo.feature:13..19"
      end

      it "is file:line:line:line for an arbitrary set of lines" do
        expect( Location.new("foo.feature", [1, 3, 5]).to_s ).to eq "foo.feature:1:3:5"
      end
    end

    describe "matches" do
      let(:matching) { Location.new(file, line) }
      let(:same_file_other_line) { Location.new(file, double) }
      let(:not_matching) { Location.new(other_file, line) }
      let(:other_file) { double }

      context 'a precise location' do
        let(:precise) { Location.new(file, line) }

        it "matches a precise location of the same file and line" do
          expect( matching ).to be_match(precise)
        end

        it "does not match a precise location on a different line in the same file" do
          expect( matching ).not_to be_match(same_file_other_line)
        end

      end

      context 'a wildcard' do
        let(:wildcard) { Location.new(file) }

        it "matches any location with the same filename" do
          expect( wildcard ).to be_match(matching)
        end

        it "is matched by any location of the same file" do
          expect( matching ).to be_match(wildcard)
        end

        it "does not match a location in a different file" do
          expect( wildcard ).not_to be_match(not_matching)
        end
      end
    end

    describe "created from source location" do
      context "when the location is in the tree below pwd" do
        it "create a relative path from pwd" do
          expect( Location.from_source_location("#{Dir.pwd}/path/file.rb", 1).file ).to eq "path/file.rb"
        end
      end

      context "when the location is in an installed gem" do
        it "create a relative path from the gem directory" do
          expect( Location.from_source_location("/path/gems/gem-name/path/file.rb", 1).file ).to eq "gem-name/path/file.rb"
        end
      end

      context "when the location is neither below pwd nor in an installed gem" do
        it "use the absolute path to the file" do
          # Use File.expand on expectation to ensure tests work on multiple platform.
          # On Windows, it will return "C:/path/file.rb" as an absolute path while it will return "/path/file.rb" on Linux.
          expect( Location.from_source_location("/path/file.rb", 1).file ).to eq File.expand_path("/path/file.rb")
        end
      end
    end

    describe "created from file-colon-line" do
      it "handles also Windows paths" do
        # NOTE: running this test on Windows will produce "c:/path/file.rb", but "c:\path\file.rb" on Linux.
        expect( Location.from_file_colon_line("c:\\path\\file.rb:123").file ).to match(/c:(\\|\/)path(\\|\/)file.rb/)
      end
    end

    describe "created of caller" do
      it "use the location of the caller" do
        expect( Location.of_caller.to_s ).to be_included_in caller[0]
      end

      context "when specifying additional caller depth" do
        it "use the location of the n:th caller" do
          expect( Location.of_caller(1).to_s ).to be_included_in caller[1]
        end
      end
    end
  end
end
