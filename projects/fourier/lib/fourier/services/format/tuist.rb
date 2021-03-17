# frozen_string_literal: true
module Fourier
  module Services
    module Format
      class Tuist < Base
        attr_reader :fix

        def initialize(fix:)
          @fix = fix
        end

        def call
          puts "yolo"
          # Kernel.system(swiftformat_path, "--lint", ".") || abort
        end
      end
    end
  end
end
