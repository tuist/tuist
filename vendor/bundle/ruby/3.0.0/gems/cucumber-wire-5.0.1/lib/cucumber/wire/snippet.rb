module Cucumber
  module Wire
    module Snippet
      class Generator
        def initialize(connections)
          # This array is shared mutable state with the wire language.
          @connections = connections
        end

        def call(code_keyword, step_name, multiline_arg, snippet_type)
          @connections.snippets(code_keyword, step_name, MultilineArgClassName.new(multiline_arg).to_s).join("\n")
        end

        class MultilineArgClassName
          def initialize(arg)
            arg.describe_to(self)
            @result = ""
          end

          def data_table(*)
            @result = "Cucumber::MultilineArgument::DataTable"
          end

          def doc_string(*)
            @result = "Cucumber::MultilineArgument::DocString"
          end

          def to_s
            @result
          end
        end
      end
    end
  end
end
