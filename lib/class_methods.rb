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
        add_default_includes!(options)
        find_every_without_default_includes(options)
      end
      alias_method_chain(:find_every, :default_includes)
      
      # Adds the default includes onto the <tt>:options</tt> hash if no includes are specified
      def add_default_includes!(options)
        return if options[:include] or default_includes.blank?
        options[:include] = default_includes
      end
      
      # Overwrite than renames join tables if clashes are found
      def add_joins!(sql, options, scope = :auto)
        scope = scope(:find) if :auto == scope
        join = (scope && scope[:joins]) || options[:joins]
        return if join.blank?
        extend_sql_avoiding_table_naming_clashes!(sql, scope && scope[:joins])
        extend_sql_avoiding_table_naming_clashes!(sql, options[:joins])
      end
      
      # Returns the names (or aliases if used) of each table used in a JOIN fragment
      def table_aliases_from_join_fragment(sql)
        return [] if sql.blank?
        return sql.scan(/JOIN\s+(`[^`]`|\S+)(?:\s+(?:AS\s+)?(`[^`]`|\S+))?/i).collect do |name|
          ((name[1] =~ /ON/i) ? name[0] : (name[1] || name[0])).gsub(/^`(.*)`$/, '\1')
        end
      end
      
      # Appends +addition+ to +sql+ by checking for table name clashes between the two
      # fragments. Table aliases in +sql+ are changed as necessary before appending +addition+.
      # It's done this way round so that manually specifying <tt>:joins</tt> retains the table name
      # you specify, reducing the potential for confusion.
      def extend_sql_avoiding_table_naming_clashes!(sql, addition)
        used_table_aliases = table_aliases_from_join_fragment(addition)
        table_aliases_from_join_fragment(sql).each do |join_table_alias|
          if used_table_aliases.include?(join_table_alias)
            i = 0
            begin
              i += 1
              new_alias = "renamed_join_table_#{i}"
            end until !used_table_aliases.include?(new_alias)
            convert_table_name_to_new_alias!(sql, join_table_alias, new_alias)
          end
          used_table_aliases << (new_alias || join_table_alias)
        end
        sql << " #{addition} "
      end
      
      # Modifies the SQL fragment such that every instance of +old_table_name+
      # is replaced by or aliased using (in JOIN ... AS blocks) +new_alias+.
      def convert_table_name_to_new_alias!(sql, old_table_name, new_alias)
        regex = Regexp.new("(?:(?:JOIN|AS)?\\s+|\\()`?#{old_table_name}`?(?:\\s+(?:AS\\s+)?(?:`[^`]`|\\S+)|\\.|\\s)", Regexp::IGNORECASE)
        sql.gsub!(regex) do |match|
          prefix = (match =~ /^\(/) ? '(' : ''
          suffix = match.gsub(/^.*?(\s+ON|.)$/i, '\1')
          if test = match.match(/^JOIN\s+(?:`[^`]`|\S+)(\s+(?:AS\s+)?(?:`[^`]`|\S+))/i) and !(test.captures.first =~ /^ ON$/i)
            # If the table name is already aliased within this match, don't replace it
            result = match
          else
            replacement = "JOIN `#{old_table_name}` AS #{new_alias}" if match =~ /^JOIN\s/i
            replacement = "AS #{new_alias}" if match =~ /^AS\s/i
            replacement = " #{new_alias}" unless match =~ /^(JOIN|AS)\s/i
            result = "#{prefix}#{replacement}#{suffix}"
          end
          result
        end
      end
    
    end
  end
end
