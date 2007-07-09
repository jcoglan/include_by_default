module ActiveRecord #:nodoc:
  class Base
    class << self
    
      def include_by_default(associations)
        write_inheritable_array("include_by_default", associations || {})
      end
      
      def default_includes
        read_inheritable("include_by_default")
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
  