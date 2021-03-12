# frozen_string_literal: true

require 'set'

module LightweightSerializer
  class Serializer
    attr_reader :options

    def self.inherited(base)
      base.defined_attributes = defined_attributes.deep_dup || {}
      base.defined_nested_serializers = defined_nested_serializers.deep_dup || {}
      base.allowed_options = allowed_options.deep_dup || Set.new
      super
    end

    class<<self
      def allow_options(*option_names)
        self.allowed_options += option_names
      end

      def group(group_name, &blk)
        with_options(group: group_name, &blk)
      end

      def attribute(name, condition: nil, group: nil, **documentation_params, &blk)
        defined_attributes[name.to_sym] = Attribute.new(
          attr_name:     name,
          group:         group,
          condition:     condition,
          documentation: documentation_params,
          block:         blk
        )
        allowed_options << condition if condition.present?
      end

      def remove_attribute(name)
        defined_attributes.delete(name.to_sym)
      end

      def nested(name, serializer:, group: nil, condition: nil, **documentation_params, &blk)
        defined_nested_serializers[name.to_sym] = NestedResource.new(
          attr_name:     name,
          block:         blk,
          condition:     condition,
          serializer:    serializer,
          documentation: documentation_params,
          group:         group,
          array:         false
        )
        self.allowed_options += serializer.allowed_options
        allowed_options << condition if condition.present?
      end

      def collection(name, serializer:, group: nil, condition: nil, **documentation_params, &blk)
        defined_nested_serializers[name.to_sym] = NestedResource.new(
          attr_name:     name,
          block:         blk,
          condition:     condition,
          serializer:    serializer,
          documentation: documentation_params,
          group:         group,
          array:         true
        )
        self.allowed_options += serializer.allowed_options
        allowed_options << condition if condition.present?
      end

      def no_root!
        @skip_root_node = true
      end

      attr_reader :defined_attributes, :defined_nested_serializers, :skip_root_node, :allowed_options

      protected

      attr_writer :defined_attributes, :defined_nested_serializers, :allowed_options
    end

    def initialize(object_or_collection, **options)
      @object_or_collection = object_or_collection
      @options = options
    end

    def as_json
      result = if @object_or_collection.is_a?(Array) || @object_or_collection.is_a?(ActiveRecord::Relation)
                 @object_or_collection.map { |o| serialized_object(o) }
               else
                 serialized_object(@object_or_collection)
               end

      if self.class.skip_root_node || options[:skip_root]
        result
      else
        { data: result }.tap do |final_hash|
          final_hash[:meta] = options[:meta] if options[:meta].present?
        end
      end
    end

    private

    def serialized_object(object)
      return nil if object.nil?

      result = {}

      self.class.defined_attributes.each do |attr_name, attribute_config|
        next if attribute_config.condition && !options[attribute_config.condition]

        if attribute_config.group.present?
          result[attribute_config.group] ||= {}
          result[attribute_config.group][attr_name] = block_or_attribute_from_object(object, attribute_config)
        else
          result[attr_name] = block_or_attribute_from_object(object, attribute_config)
        end
      end

      self.class.defined_nested_serializers.each do |attr_name, attribute_config|
        next if attribute_config.condition && !options[attribute_config.condition]

        nested_object = block_or_attribute_from_object(object, attribute_config)
        value = if nested_object.nil?
                  nil
                else
                  sub_options = options_for_nested_serializer(attribute_config)
                  attribute_config.serializer.new(nested_object, **sub_options).as_json
                end

        if attribute_config.group.present?
          result[attribute_config.group] ||= {}
          result[attribute_config.group][attr_name] = value
        else
          result[attr_name] = value
        end
      end

      result
    end

    def options_for_nested_serializer(attribute_config)
      options.
        slice(*attribute_config.serializer.allowed_options).
        merge(skip_root: true)
    end

    def block_or_attribute_from_object(object, attribute_config)
      if attribute_config.block
        instance_exec(object, &attribute_config.block)
      else
        object.public_send(attribute_config.attr_name)
      end
    end
  end
end
