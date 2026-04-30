module JSE
  module Functors
    module Utils
      def self.eval_arg(env, arg)
        arg.respond_to?(:apply) ? env.eval(arg) : arg
      end

      def self.not_fn(env, *args)
        return true if args.empty?
        !eval_arg(env, args[0])
      end

      def self.and_fn(env, *args)
        return true if args.empty?
        args.each do |arg|
          return false unless eval_arg(env, arg)
        end
        true
      end

      def self.or_fn(env, *args)
        return false if args.empty?
        args.each do |arg|
          val = eval_arg(env, arg)
          return val if val
        end
        false
      end

      def self.listp(env, *args)
        return false if args.empty?
        eval_arg(env, args[0]).is_a?(Array)
      end

      def self.mapp(env, *args)
        return false if args.empty?
        eval_arg(env, args[0]).is_a?(Hash)
      end

      def self.nullp(env, *args)
        return true if args.empty?
        eval_arg(env, args[0]).nil?
      end

      def self.get_fn(env, *args)
        raise "$get requires (collection, key)" if args.length < 2
        coll = eval_arg(env, args[0])
        key = eval_arg(env, args[1])
        if coll.is_a?(Hash)
          coll[key]
        elsif coll.is_a?(Array)
          raise "$get on list requires integer index" unless key.is_a?(Integer)
          raise IndexError, "Index #{key} out of range" if key < 0 || key >= coll.length
          coll[key]
        else
          raise "$get first argument must be map or list"
        end
      end

      def self.set_fn(env, *args)
        raise "$set requires (collection, key, value)" if args.length < 3
        coll = eval_arg(env, args[0])
        key = eval_arg(env, args[1])
        val = eval_arg(env, args[2])
        if coll.is_a?(Hash)
          coll[key] = val
        elsif coll.is_a?(Array)
          raise "$set on list requires integer index" unless key.is_a?(Integer)
          coll[key] = val
        else
          raise "$set first argument must be map or list"
        end
        coll
      end

      def self.del_fn(env, *args)
        raise "$del requires (collection, key)" if args.length < 2
        coll = eval_arg(env, args[0])
        key = eval_arg(env, args[1])
        if coll.is_a?(Hash)
          coll.delete(key) { raise KeyError, "Key '#{key}' not found" }
        elsif coll.is_a?(Array)
          raise "$del on list requires integer index" unless key.is_a?(Integer)
          coll.delete_at(key)
        else
          raise "$del first argument must be map or list"
        end
        coll
      end

      def self.conj(env, *args)
        raise "$conj requires exactly 2 arguments" unless args.length == 2
        elem = eval_arg(env, args[0])
        lst = eval_arg(env, args[1])
        raise "$conj second argument must be a list" unless lst.is_a?(Array)
        lst + [elem]
      end

      def self.eq2(env, *args)
        evaluated = args.map { |a| eval_arg(env, a) }
        case evaluated.length
        when 1 then true
        when 2 then evaluated[0] == evaluated[1]
        else
          evaluated.each_cons(2).all? { |a, b| a == b }
        end
      end

      UTILS_FUNCTORS = {
        "$not"   => method(:not_fn),
        "$list?" => method(:listp),
        "$map?"  => method(:mapp),
        "$null?" => method(:nullp),
        "$get"   => method(:get_fn),
        "$set"   => method(:set_fn),
        "$del"   => method(:del_fn),
        "$conj"  => method(:conj),
        "$and"   => method(:and_fn),
        "$or"    => method(:or_fn),
      }.freeze
    end
  end
end
