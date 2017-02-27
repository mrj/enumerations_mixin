# Copyright (c) 2005 Trevor Squires
# Released under the MIT License.  See the LICENSE file for more details.

module ActiveRecord
  module VirtualEnumerations # :nodoc:
    class << self
      def define
        raise ArgumentError, "#{self.name}: must pass a block to define()" unless block_given?
        config = ActiveRecord::VirtualEnumerations::Config.new
        yield config
        @config = config # we only overwrite config if no exceptions were thrown
      end

      def synthesize_if_defined(const)
        return nil unless @config && (options = @config[const])
        enum_class = Object.const_set(const, Class.new(Object.const_get(options[:options][:extend]||'ActiveRecord::Base')))
        enum_class.class_eval do
          acts_as_enumerated options[:scope], on_lookup_failure: options[:options][:on_lookup_failure]
          self.table_name = options[:options][:table_name] if options[:options][:table_name]
        end
        enum_class.class_eval(&options[:post_synth_block]) if options[:post_synth_block]
        return enum_class
      end
    end

    class Config
      def initialize
        @enumeration_defs = {}
      end

      def define(arg, scope = nil, options = {}, &synth_block)
        (arg.is_a?(Array) ? arg : [arg]).each do |class_name|
          camel_name = class_name.to_s.camelize
          raise ArgumentError, "ActiveRecord::VirtualEnumerations.define - invalid class_name argument (#{class_name.inspect})" if camel_name.blank?
          raise ArgumentError, "ActiveRecord::VirtualEnumerations.define - class_name already defined (#{camel_name})" if @enumeration_defs[camel_name.to_sym]
          if scope.is_a?(Hash)
            options = scope
            scope   = nil
          end
          options.assert_valid_keys(:table_name, :extends, :on_lookup_failure)
          @enumeration_defs[camel_name.to_sym] = {scope: scope, options: options.dup, post_synth_block: synth_block}
        end
      end

      def [](arg)
        @enumeration_defs[arg]
      end
    end #class Config
  end #module VirtualEnumerations
end #module ActiveRecord

# Rails.application.config.after_initialize do
  # class Module
    # def const_missing_with_virtual_enumerations(const_id)
      # # let rails have a go at loading it
      # const_missing_without_virtual_enumerations(const_id)
    # rescue NameError, LoadError
      # # now it's our turn
      # ActiveRecord::VirtualEnumerations.synthesize_if_defined(const_id) or raise
    # end
#     
    # alias_method_chain :const_missing, :virtual_enumerations
  # end
# end
