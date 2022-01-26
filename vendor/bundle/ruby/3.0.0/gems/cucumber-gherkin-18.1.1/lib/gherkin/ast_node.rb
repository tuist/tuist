module Gherkin
  class AstNode
    attr_reader :rule_type

    def initialize(rule_type)
      @rule_type = rule_type
      @_sub_items = Hash.new { |hash, key| hash[key] = [] } # returns [] for unknown key
    end

    def add(rule_type, obj)
      @_sub_items[rule_type].push(obj)
    end

    def get_single(rule_type)
      @_sub_items[rule_type].first
    end

    def get_items(rule_type)
      @_sub_items[rule_type]
    end

    def get_token(token_type)
      get_single(token_type)
    end

    def get_tokens(token_type)
      @_sub_items[token_type]
    end
  end
end
