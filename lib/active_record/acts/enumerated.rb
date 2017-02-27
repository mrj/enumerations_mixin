# Copyright (c) 2005 Trevor Squires
# Released under the MIT License.  See the LICENSE file for more details.

module ActiveRecord
  module Acts
    module Enumerated
      def self.append_features(base)
        super
        base.extend(MacroMethods)
      end
      
      module MacroMethods
        def acts_as_enumerated(scope = nil, options = {})
          if scope.is_a?(Hash)
            options = scope
            scope   = nil
          end
          class_attribute :enumerated_scope, :enumerated_options, :enumerated_name_field
          self.enumerated_scope = scope || all
          valid_keys = [:on_lookup_failure, :name_field]
          options.assert_valid_keys(*valid_keys)
          self.enumerated_options = options.dup
          self.enumerated_name_field = enumerated_options[:name_field] || :name
          
          unless self.is_a? ActiveRecord::Acts::Enumerated::ClassMethods
            extend ActiveRecord::Acts::Enumerated::ClassMethods
            class_eval do
              include ActiveRecord::Acts::Enumerated::InstanceMethods
              validates_uniqueness_of enumerated_name_field, allow_nil: true
              #before_save :enumeration_model_update
              #before_destroy :enumeration_model_update
            end
          end
        end
      end
      
      module ClassMethods
        attr_accessor :enumeration_model_updates_permitted
        
        def enumerations_cache
          @enumerations_cache ||= enumerated_scope
        end

        def [](arg)
          case arg
          when Symbol
            rval = lookup_name(arg.id2name) and return rval
          when String
            rval = lookup_name(arg) and return rval
          when Integer
            rval = lookup_id(arg) and return rval
          when nil
            rval = nil
          else
            raise TypeError, "#{self.name}[]: argument should be a String, Symbol or Integer but got a: #{arg.class.name}"
          end
          self.send((enumerated_options[:on_lookup_failure] || :enforce_strict_literals), arg)
        end

        def lookup_id(arg)
          enumerations_cache_by_id[arg]
        end

        def lookup_name(arg)
          enumerations_cache_by_name[arg]
        end

        def include?(arg)
          case arg
            when Symbol
              return !lookup_name(arg.id2name).nil?
            when String
              return !lookup_name(arg).nil?
            when Integer
              return !lookup_id(arg).nil?
            when self
              possible_match = lookup_id(arg.id)
              return !possible_match.nil? && possible_match == arg
          end
          return false
        end

        # NOTE: purging the cache is sort of pointless because
        # of the per-process rails model.
        # By default this blows up noisily just in case you try to be more
        # clever than rails allows.
        # For those times (like in Migrations) when you really do want to
        # alter the records you can silence the carping by setting
        # enumeration_model_updates_permitted to true.
        def purge_enumerations_cache
          unless self.enumeration_model_updates_permitted
            raise "#{self.name}: cache purging disabled for your protection"
          end
          @enumerations_cache = @enumerations_cache_by_name = @enumerations_cache_by_id = nil
        end

        private

        def enumerations_cache_by_id
          @enumerations_cache_by_id ||= enumerations_cache.each_with_object({}) { |item, memo| memo[item.id] = item } # .freeze
        end
        
        def enumerations_cache_by_name
          begin
            @enumerations_cache_by_name ||= all.each_with_object({}) { |item, memo| memo[item.send(enumerated_name_field)] = item } # .freeze
          rescue NoMethodError => err
            if err.name == enumerated_name_field
              raise TypeError, "#{self.name}: you need to define a '#{enumerated_name_field}' column in the table '#{table_name}'"
            end
            raise
          end
        end

        def enforce_none(arg)
          return nil
        end

        def enforce_strict(arg)
          raise ActiveRecord::RecordNotFound, "Couldn't find a #{self.name} identified by (#{arg.inspect})"
        end

        def enforce_strict_literals(arg)
          if Integer === arg || Symbol === arg
            raise ActiveRecord::RecordNotFound, "Couldn't find a #{self.name} identified by (#{arg.inspect})"
          end
          return nil
        end

      end

      module InstanceMethods
        def ===(arg)
          case arg
            when Symbol, String, Integer, nil
              return self == self.class[arg]
            when Array
              return self.in?(*arg)
            end
          super
        end
        
        alias_method :like?, :===
        
        def in?(*list)
          for item in list
            self === item and return true
          end
          return false
        end

        def name_sym
          self.send(enumerated_name_field).to_sym
        end

        private

        # NOTE: updating the models that back an acts_as_enumerated is
        # rather dangerous because of rails' per-process model.
        # The cached values could get out of synch between processes
        # and rather than completely disallow changes I make you jump
        # through an extra hoop just in case you're defining your enumeration
        # values in Migrations.  I.e. set enumeration_model_updates_permitted = true
        def enumeration_model_update
          if self.class.enumeration_model_updates_permitted
            self.class.purge_enumerations_cache
            return true
          end
          # Ugh.  This just seems hack-ish.  I wonder if there's a better way.
          self.errors.add(enumerated_name_field, 'changes to acts_as_enumeration model instances are not permitted')
          return false
        end
      end
    end
  end
end
