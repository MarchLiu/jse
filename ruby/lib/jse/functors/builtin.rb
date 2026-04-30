module JSE
  module Functors
    module Builtin
      def self.quote(env, *args)
        args[0]
      end

      def self.eq(env, *args)
        a = args[0].respond_to?(:apply) ? env.eval(args[0]) : args[0]
        b = args[1].respond_to?(:apply) ? env.eval(args[1]) : args[1]
        a == b
      end

      def self.cond(env, *args)
        i = 0
        while i < args.length - 1
          test = args[i].respond_to?(:apply) ? env.eval(args[i]) : args[i]
          if test
            return args[i + 1].respond_to?(:apply) ? env.eval(args[i + 1]) : args[i + 1]
          end
          i += 2
        end
        # Odd number of args: last is default
        if args.length.odd?
          env.eval(args.last)
        end
      end

      def self.head(env, *args)
        lst = args[0].respond_to?(:apply) ? env.eval(args[0]) : args[0]
        raise "$head requires a list" unless lst.is_a?(Array)
        raise "$head: list is empty" if lst.empty?
        lst.first
      end

      def self.tail(env, *args)
        lst = args[0].respond_to?(:apply) ? env.eval(args[0]) : args[0]
        raise "$tail requires a list" unless lst.is_a?(Array)
        raise "$tail: list is empty" if lst.empty?
        lst[1..]
      end

      def self.atomp(env, *args)
        val = args[0].respond_to?(:apply) ? env.eval(args[0]) : args[0]
        val.nil? || val.is_a?(Integer) || val.is_a?(Float) ||
          val == true || val == false || val.is_a?(String)
      end

      def self.cons(env, *args)
        elem = args[0].respond_to?(:apply) ? env.eval(args[0]) : args[0]
        lst = args[1].respond_to?(:apply) ? env.eval(args[1]) : args[1]
        raise "$cons second argument must be a list" unless lst.is_a?(Array)
        [elem] + lst
      end

      BUILTIN_FUNCTORS = {
        "$quote" => method(:quote),
        "$eq"    => method(:eq),
        "$cond"  => method(:cond),
        "$head"  => method(:head),
        "$tail"  => method(:tail),
        "$atom?" => method(:atomp),
        "$cons"  => method(:cons),
      }.freeze
    end
  end
end
