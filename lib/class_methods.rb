module ActiveRecord #:nodoc:
  class Base
    class << self
    
      # Specifies that certain associations should be eager loaded by default on all
      # +find+ operations. Takes its arguments in the same way as the <tt>:include</tt>
      # option for the +find+ method.
      def include_by_default(*args)
        write_inheritable_attribute("include_by_default", args || [])
      end
      
      # Returns the default set of <tt>:includes</tt> used for +find+ operations.
      def default_includes
        read_inheritable_attribute("include_by_default").to_a
      end
      
    private
      
      # Wrapper for +find_every+ - all other finders are routed through this method.
      def find_every_with_default_includes(options)
        add_default_includes(options)
        find_every_without_default_includes(options)
      rescue ActiveRecord::StatementInvalid
        convert_problematic_includes_to_joins(options)
        find_every_without_default_includes(options)
      end
      alias_method_chain(:find_every, :default_includes)
      
      # Adds the default includes onto the <tt>:options</tt> hash if no includes are specified
      def add_default_includes(options)
        return unless options[:include].nil? and !default_includes.blank?
        options[:include] = default_includes
      end
    
    end
  end
end
