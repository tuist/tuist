# frozen_string_literal: true
require "tmpdir"
require "json"

module Fourier
  module Services
    class Benchmark < Base
      def call
        Dir.mktmpdir do |tmp_dir|
          ::CLI::UI::Frame.open("Building supporting tools") do
            puts "Building the benchmarking tool"
            Services::Build::Benchmark.call(configuration: "release")

            puts "Building the fixture generator"
            Services::Build::Fixture.call(configuration: "release")
          end

          ::CLI::UI::Frame.open("Generating fixtures") do
            puts "Generating a Tuist project with 50 projects"
            Utilities::System.fixturegen(
              "--path", File.join(tmp_dir, "50_projects"),
              "--projects", "50"
            )
            puts "Generating a Tuist project with 2 projects and 2000 sources"
            Utilities::System.fixturegen(
              "--path", File.join(tmp_dir, "2000_sources"),
              "--projects", "2",
              "--sources", "2000"
            )
          end

          puts "Storing the list of fixtures to benchmark"
          fixture_list_path = File.join(tmp_dir, "fixtures.json")
          fixtures = {
            "paths" => [
              File.join(tmp_dir, "50_projects"),
              File.join(tmp_dir, "2000_sources"),
              File.join(Constants::ROOT_DIRECTORY, "fixtures/ios_app_with_static_frameworks"),
              File.join(Constants::ROOT_DIRECTORY, "fixtures/ios_app_with_framework_and_resources"),
              File.join(Constants::ROOT_DIRECTORY, "fixtures/ios_app_with_transitive_framework"),
              File.join(Constants::ROOT_DIRECTORY, "fixtures/ios_app_with_xcframeworks"),
            ],
          }
          File.write(fixture_list_path, fixtures.to_json)

          ::CLI::UI::Frame.open("Building Tuist") do
            Dir.chdir(Constants::TUIST_DIRECTORY) do
              Utilities::System.system("swift", "build", "--product", "tuist", "--configuration", "release")
              Utilities::System.system("swift", "build", "--product", "tuistenv", "--configuration", "release")
              Utilities::System.system("swift", "build", "--product", "ProjectDescription", "--configuration",
                "release")
            end
          end

          ::CLI::UI::Frame.open("Downloading the latest version of Tuist") do
            Utilities::System.system(File.join(Constants::TUIST_DIRECTORY, ".build/release/tuistenv"), "update")
            Utilities::System.system(File.join(Constants::TUIST_DIRECTORY, ".build/release/tuistenv"), "version")
          end

          ::CLI::UI::Frame.open("Benchmarking") do
            Utilities::System.system(
              File.join(Constants::TUISTBENCH_DIRECTORY, ".build/release/tuistbench"),
              "-b", File.join(Constants::TUIST_DIRECTORY, ".build/release/tuist"),
              "-r", File.join(Constants::TUIST_DIRECTORY, ".build/release/tuistenv"),
              "-l", fixture_list_path,
              "--format", "markdown"
            )
          end
        end
      end
    end
  end
end
