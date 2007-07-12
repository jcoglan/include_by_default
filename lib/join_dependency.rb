module ActiveRecord #:nodoc:
  module Associations #:nodoc:
    module ClassMethods #:nodoc:
      class JoinDependency
      
        # Wrapper for +instantiate+, which accepts a set of join table information and adds
        # it into the JoinDependency's properties so that the join table data gets eager loaded.
        def instantiate_with_reloading_dropped_associations(rows, join_tables = nil)
          join_tables.to_a.each do |join_table|
            next unless rows.first and rows.first.keys.include?(join_table[:first_column])
            @associations << join_table[:association]
            reflection = join_base.reflections[join_table[:association]]
            @reflections << reflection
            @joins << JoinAssociation.new(reflection, self, join_base)
          end
          instantiate_without_reloading_dropped_associations(rows)
        end
        alias_method_chain(:instantiate, :reloading_dropped_associations)
      
      end
    end
  end
end
