module ActiveRecord #:nodoc:
  class Base
    class << self
    
      # When +convert_problematic_includes_to_joins+ is used, the column names for the JOIN will not
      # be writtten out in SQL so the JOINed tables data is not actually loaded. This wrapper adds
      # column aliases for the JOINed tables so their data is present in the result set.
      def column_aliases_with_eager_loading_from_joins(join_dependency)
        sql = column_aliases_without_eager_loading_from_joins(join_dependency)
        final_column_alias = sql.scan(/t(\d+)_r(\d+)/).last.map(&:to_i)
        @join_table_aliases_for_eager_loading.to_a.each_with_index do |join_table, i|
          join_columns = []
          Kernel.const_get(join_table[:class_name]).column_names.each_with_index do |column_name, j|
            column_alias = "t#{final_column_alias[0] + i + 1}_r#{j}"
            @join_table_aliases_for_eager_loading[i][:first_column] ||= column_alias
            join_columns << "#{join_table[:table_alias]}.#{connection.quote_column_name column_name} AS #{column_alias}"
          end
          sql = ([sql] + join_columns) * ', '
        end
        sql
      end
      alias_method_chain(:column_aliases, :eager_loading_from_joins)
      
      # Returns a JOIN statement for a HABTM association, with the given numeric index used for table aliasing,
      # and the class name and table alias used for the association - this is used to manually load column names for eager loading.
      def join_fragment_for_has_and_belongs_to_many_association(association, i = 1)
        association = reflect_on_association(association) unless association.is_a?(ActiveRecord::Reflection::AssociationReflection)
        return nil unless association and association.macro == :has_and_belongs_to_many
        
        assoc_class = Kernel.const_get(association.class_name)
        opts = association.options
        
        join_table = opts[:join_table]
        join_table_alias = "ibd_join_table_#{i}"
        join_foreign_key = opts[:foreign_key]
        assoc_table = assoc_class.table_name
        assoc_table_alias = "ibd_assoc_table_#{i}"
        assoc_primary_key = assoc_class.primary_key
        assoc_foreign_key = opts[:association_foreign_key]
        
        sql = <<-end_of_sql
          LEFT OUTER JOIN #{join_table} AS #{join_table_alias}
          ON #{join_table_alias}.#{join_foreign_key} = #{table_name}.#{primary_key}
          LEFT OUTER JOIN #{assoc_table} AS #{assoc_table_alias}
          ON #{assoc_table_alias}.#{assoc_primary_key} = #{join_table_alias}.#{assoc_foreign_key}
        end_of_sql
        [sql.gsub(/\n/, '').gsub(/\s+/, ' '), association.class_name, assoc_table_alias]
      end
      
      # Returns a JOIN statement for a <tt>has_many :through</tt> association, with the given numeric index used for table aliasing,
      # and the class name and table alias used for the association - this is used to manually load column names for eager loading.
      def join_fragment_for_has_many_through_association(association, i = 1)
        association = reflect_on_association(association) unless association.is_a?(ActiveRecord::Reflection::AssociationReflection)
        return nil unless association and association.macro == :has_many and association.options[:through]
        
        through_assoc = reflect_on_association(association.options[:through])
        through_class = Kernel.const_get(through_assoc.class_name)
        source_assoc = through_class.reflect_on_association(association.name)
        source_assoc ||= through_class.reflect_on_association(association.name.to_s.singularize.intern)
        source_class = Kernel.const_get(source_assoc.class_name)
        
        join_table = through_class.table_name
        join_table_alias = "ibd_join_table_#{i}"
        join_foreign_key = through_assoc.options[:foreign_key]
        assoc_table = source_class.table_name
        assoc_table_alias = "ibd_assoc_table_#{i}"
        assoc_primary_key = source_class.primary_key
        assoc_foreign_key = source_assoc.options[:foreign_key]
        
        sql = <<-end_of_sql
          LEFT OUTER JOIN #{join_table} AS #{join_table_alias}
          ON #{join_table_alias}.#{join_foreign_key} = #{table_name}.#{primary_key}
          LEFT OUTER JOIN #{assoc_table} AS #{assoc_table_alias}
          ON #{assoc_table_alias}.#{assoc_primary_key} = #{join_table_alias}.#{assoc_foreign_key}
        end_of_sql
        [sql.gsub(/\n/, '').gsub(/\s+/, ' '), source_assoc.class_name, assoc_table_alias]
      end
    
    end
  end
end
