module JSE
  module Ast
    class LiteralNode < AstNode
      def initialize(value, env)
        super(env)
        @value = value
      end

      attr_reader :value

      def apply(_call_env)
        @value
      end

      def to_json
        @value
      end
    end

    class SymbolNode < AstNode
      def initialize(name, env)
        super(env)
        @name = name
      end

      attr_reader :name

      def apply(call_env)
        val = call_env.resolve(@name)
        raise NameError, "Symbol '#{@name}' not found" if val.nil?
        val
      end

      def to_json
        @name
      end
    end

    class ArrayNode < AstNode
      def initialize(elements, env)
        super(env)
        @elements = elements
      end

      attr_reader :elements

      def apply(call_env)
        return [] if @elements.empty?

        first = @elements.first
        if first.is_a?(SymbolNode) && JSE::Parser.symbol?(first.name)
          apply_function_call(call_env, first.name)
        else
          @elements.map { |e| call_env.eval(e) }
        end
      end

      def to_json
        @elements.map(&:to_json)
      end

      private

      def apply_function_call(call_env, symbol)
        rest = @elements[1..]
        if symbol == "$quote"
          # Pass unevaluated
          args = rest.map(&:to_json)
          return apply_functor(call_env, symbol, args)
        end
        evaluated = rest.map { |e| call_env.eval(e) }
        apply_functor(call_env, symbol, evaluated)
      end

      def apply_functor(call_env, symbol, args)
        functor = call_env.resolve(symbol)
        raise NameError, "Unknown operator: #{symbol}" if functor.nil?
        functor.call(call_env, *args)
      end
    end

    class ObjectNode < AstNode
      def initialize(dict, env)
        super(env)
        @dict = dict
      end

      def apply(call_env)
        @dict.transform_values { |v| call_env.eval(v) }
      end

      def to_json
        @dict.transform_values(&:to_json)
      end
    end

    class ExpressionNode < AstNode
      def initialize(operator, value, metadata, env)
        super(env)
        @operator = operator
        @value = value
        @metadata = metadata
      end

      attr_reader :operator, :value, :metadata

      def apply(call_env)
        functor = call_env.resolve(@operator)
        raise NameError, "Unknown operator: #{@operator}" if functor.nil?

        evaluated_meta = @metadata.transform_values { |v| deep_eval(call_env, v) }
        call_env.set_meta(evaluated_meta)
        begin
          args = case @operator
          when "$quote"
            [@value]
          when "$expr"
            [call_env.eval(@value)]
          when "$sql"
            # $sql receives raw JSON stored in LiteralNode by parser
            if @value.is_a?(LiteralNode)
              [@value.value]
            else
              [@value]
            end
          else
            if @value.is_a?(ArrayNode)
              @value.elements.map { |e| deep_eval(call_env, e) }
            else
              [call_env.eval(@value)]
            end
          end

          functor.call(call_env, *args)
        ensure
          call_env.clear_meta
        end
      end

      def to_json
        result = { @operator => @value.to_json }
        @metadata.each { |k, v| result[k] = v }
        result
      end

      private

      def deep_eval(env, value)
        evaluated = env.eval(value)
        case evaluated
        when Array
          evaluated.map { |item| deep_eval(env, item) }
        when Hash
          evaluated.transform_values { |v| deep_eval(env, v) }
        else
          evaluated
        end
      end
    end

    class QuoteNode < AstNode
      def initialize(value, env)
        super(env)
        @value = value
      end

      def apply(_call_env)
        @value
      end

      def to_json
        if @value.respond_to?(:to_json)
          ["$quote", @value.to_json]
        else
          ["$quote", @value]
        end
      end
    end

    class LambdaNode < AstNode
      def initialize(params, body, closure_env)
        super(closure_env)
        @params = params
        @body = body
        @closure_env = closure_env
      end

      def apply(call_env, *args)
        if args.length != @params.length
          raise ArgumentError, "Lambda expects #{@params.length} args, got #{args.length}"
        end

        call_env = JSE::Env.new(parent: @closure_env)
        @params.zip(args).each { |param, arg| call_env.set(param, arg) }
        call_env.eval(@body)
      end

      def to_json
        "<lambda>"
      end
    end
  end
end
