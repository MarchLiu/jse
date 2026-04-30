module JSE
  class Parser
    def self.symbol?(s)
      return false if s == "$*"
      s.is_a?(String) && s.start_with?("$") && !s.start_with?("$$")
    end

    def self.unescape(s)
      s.is_a?(String) && s.start_with?("$$") ? s[1..] : s
    end

    def initialize(env)
      @env = env
    end

    def parse(expr)
      case expr
      when nil, true, false, Integer, Float
        Ast::LiteralNode.new(expr, @env)
      when String
        if self.class.symbol?(expr)
          Ast::SymbolNode.new(expr, @env)
        else
          Ast::LiteralNode.new(self.class.unescape(expr), @env)
        end
      when Array
        parse_list(expr)
      when Hash
        parse_dict(expr)
      else
        Ast::LiteralNode.new(expr, @env)
      end
    end

    private

    def parse_list(lst)
      return Ast::ArrayNode.new([], @env) if lst.empty?

      first = lst.first
      if first == "$quote"
        value = lst.length > 1 ? lst[1] : nil
        return Ast::QuoteNode.new(value, @env)
      end

      if first.is_a?(String) && self.class.symbol?(first)
        elements = lst[1..].map { |e| parse(e) }
        return Ast::ExpressionNode.new(first, Ast::ArrayNode.new(elements, @env), {}, @env)
      end

      elements = lst.map { |e| parse(e) }
      Ast::ArrayNode.new(elements, @env)
    end

    def parse_dict(dict)
      symbol_keys = dict.keys.select { |k| self.class.symbol?(k) }

      if symbol_keys.empty?
        result = {}
        dict.each do |k, v|
          parsed_key = self.class.unescape(k)
          result[parsed_key] = parse(v)
        end
        return Ast::ObjectNode.new(result, @env)
      end

      if symbol_keys.length == 1
        operator = symbol_keys.first

        if operator == "$quote"
          return Ast::QuoteNode.new(dict[operator], @env)
        end

        # $sql: pass raw JSON directly (bypass JSE parsing)
        if operator == "$sql"
          raw_value = dict[operator]
          metadata = {}
          dict.each do |k, v|
            next if k == operator
            metadata[self.class.unescape(k)] = v
          end
          return Ast::ExpressionNode.new(operator, Ast::LiteralNode.new(raw_value, @env), metadata, @env)
        end

        parsed_value = parse(dict[operator])
        metadata = {}
        dict.each do |k, v|
          next if k == operator
          metadata[self.class.unescape(k)] = parse(v)
        end
        return Ast::ExpressionNode.new(operator, parsed_value, metadata, @env)
      end

      raise "JSE structure error: object cannot have multiple operator keys"
    end
  end
end
