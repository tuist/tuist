# frozen_string_literal: true

module Cucumber
  module LoadPath
    def add_dirs(*dirs)
      dirs.each do |dir|
        $LOAD_PATH.unshift(dir) unless $LOAD_PATH.include?(dir)
      end
    end

    module_function :add_dirs
  end
end

Cucumber::LoadPath.add_dirs('lib')
