module JSE
  module Functors
    module Lisp
      def self.eval_fn(env, *args)
        raise "$eval requires 1 argument" if args.empty?
        env.eval(args[0])
      end

      def self.apply_fn(env, *args)
        raise "$apply requires (functor, arglist)" if args.length < 2
        functor = args[0].respond_to?(:apply) ? env.eval(args[0]) : args[0]
        arglist = args[1].respond_to?(:apply) ? env.eval(args[1]) : args[1]
        raise "$apply second argument must be a list" unless arglist.is_a?(Array)
        functor.call(env, *arglist)
      end

      def self.lambda_fn(env, *args)
        raise "$lambda requires (params, body)" if args.length < 2
        params_raw = args[0]
        body = args[1]

        params = if params_raw.is_a?(Ast::ArrayNode)
          params_raw.elements.map { |e| e.is_a?(Ast::SymbolNode) ? e.name : e }
        elsif params_raw.is_a?(Ast::SymbolNode)
          [params_raw.name]
        elsif params_raw.is_a?(Array)
          params_raw
        else
          [params_raw.to_s]
        end

        Ast::LambdaNode.new(params, body, env)
      end

      def self.def_fn(env, *args)
        raise "$def requires (name, value)" if args.length < 2
        name_node = args[0]
        name = if name_node.is_a?(Ast::SymbolNode)
          name_node.name
        elsif name_node.is_a?(String)
          name_node
        else
          name_node.to_s
        end
        value = args[1].respond_to?(:apply) ? env.eval(args[1]) : args[1]
        env.register(name, value)
        value
      end

      def self.defn(env, *args)
        raise "$defn requires (name, params, body)" if args.length < 3
        name_node = args[0]
        name = if name_node.is_a?(Ast::SymbolNode)
          name_node.name
        else
          name_node.to_s
        end
        lambda_result = lambda_fn(env, args[1], args[2])
        env.register(name, lambda_result)
        lambda_result
      end

      LISP_FUNCTORS = {
        "$eval"   => method(:eval_fn),
        "$apply"  => method(:apply_fn),
        "$lambda" => method(:lambda_fn),
        "$def"    => method(:def_fn),
        "$defn"   => method(:defn),
      }.freeze
    end
  end
end
