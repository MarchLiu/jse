module JSE
  module Ast
    class AstNode
      def initialize(env)
        @env = env
      end

      attr_reader :env

      def apply(call_env)
        raise NotImplementedError
      end

      def to_json
        raise NotImplementedError
      end
    end
  end
end
