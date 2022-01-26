# frozen_string_literal: true

module Cucumber
  # Generates generic file structure for a cucumber project
  class ProjectInitializer
    def run
      create_directory('features')
      create_directory('features/step_definitions')
      create_directory('features/support')
      create_file('features/support/env.rb')
    end

    private

    def create_directory(dir_name)
      create_directory_or_file dir_name, true
    end

    def create_file(file_name)
      create_directory_or_file file_name, false
    end

    def create_directory_or_file(file_name, directory)
      file_type = if directory
                    :mkdir_p
                  else
                    :touch
                  end

      report_exists(file_name) || return if File.exist?(file_name)

      report_creating(file_name)
      FileUtils.send file_type, file_name
    end

    def report_exists(file)
      puts "   exist   #{file}"
    end

    def report_creating(file)
      puts "  create   #{file}"
    end
  end
end
