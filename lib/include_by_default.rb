module ActiveRecord #:nodoc:
  class Base
    class << self
    
      def include_by_default(*args)
        write_inheritable_attribute("include_by_default", args || [])
      end
      
      def default_includes
        read_inheritable_attribute("include_by_default")
      end
      
    private
      
      def find_initial_with_default_includes(options)
        options[:include] ||= default_includes
        find_initial_without_default_includes(options)
      end
      alias_method(:find_initial_without_default_includes, :find_initial)
      alias_method(:find_initial, :find_initial_with_default_includes)
      
      def find_every_with_default_includes(options)
        options[:include] ||= default_includes
        find_every_without_default_includes(options)
      end
      alias_method(:find_every_without_default_includes, :find_every)
      alias_method(:find_every, :find_every_with_default_includes)
      
      def find_from_ids_with_default_includes(ids, options)
        options[:include] ||= default_includes
        find_from_ids_without_default_includes(ids, options)
      end
      alias_method(:find_from_ids_without_default_includes, :find_from_ids)
      alias_method(:find_from_ids, :find_from_ids_with_default_includes)
    
    end
  end
end
  