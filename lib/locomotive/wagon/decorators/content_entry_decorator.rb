module Locomotive
  module Wagon

    class ContentEntryDecorator < Locomotive::Steam::Decorators::I18nDecorator

      include ToHashConcern
      include PersistAssetsConcern

      attr_accessor :__base_path__, :__content_assets_pusher__, :__persist_content__

      DEFAULT_ATTRIBUTES = %i(_slug seo_title meta_keywords meta_description).freeze

      def initialize(object, locale = nil, base_path, content_assets_pusher, persist_content: false)
        self.__base_path__ = base_path
        self.__content_assets_pusher__ = content_assets_pusher
        self.__persist_content__ = persist_content
        super(object, locale, nil)
      end

      def _id=(id)
        __getobj__[:remote_id] = id
      end

      def _id
        __getobj__[:remote_id] || self._slug
      end

      def __attributes__
        DEFAULT_ATTRIBUTES + fields.no_associations.map { |f| f.name.to_sym }
      end

      def method_missing(name, *args, &block)
        if field = fields.by_name(name.to_s)
          method_name = :"decorate_#{field.type}_field"
          respond_to?(method_name) ? send(method_name, super) : super
        else
          super
        end
      end

      def decorate_text_field(value)
        replace_with_content_assets!(value)
      end

      def decorate_file_field(value)
        return nil if value.nil? || value.filename.blank?
        asset_io(File.join(value.base, value.filename))
      end

      def decorate_date_time_field(value)
        return nil if value.nil?
        value.utc.try(:iso8601)
      end

      def decorate_date_field(value)
        value.try(:iso8601)
      end

      def decorate_json_field(value)
        value.to_json
      end

      alias :decorate_time_field :decorate_date_time_field

      def to_hash
        hash = super

        # send the position only on a full-data push so a re-deploy can reorder the
        # entries, while a back-office reordering stays untouched on a content push.
        # added before the "empty entry" check so a minimal entry still carries its order.
        # nil is skipped (keep the engine default), but 0 is a valid position.
        if __persist_content__
          position = _position
          hash[:_position] = position unless position.nil?
        end

        hash.keys == DEFAULT_ATTRIBUTES ? {} : hash
      end

      private

      def _position
        __getobj__[:_position]
      end

      def fields
        __getobj__.content_type.fields
      end

    end

    class ContentEntryWithLocalizedAttributesDecorator < ContentEntryDecorator

      def __attributes__
        %i(_slug) + fields.localized_names(include_select_field_id: false)
      end

    end

    class ContentEntryWithOnlyRelationshipsDecorator < ContentEntryDecorator

      def __attributes__
        fields.associations.map { |f| f.name.to_sym }
      end

      def decorate_belongs_to_field(value)
        return nil if value.nil?
        value._slug.try(:[], __locale__.to_s)
      end

      def decorate_many_to_many_field(value)
        entries = value.all

        if entries.empty?
          nil
        elsif entries.size == 1 && entries.first == ''
          [nil]
        else
          entries.map { |entry| entry._slug.try(:[], __locale__) }.compact
        end
      end

      def decorate_has_many_field(value)
        nil
      end

    end

  end
end
