require_relative '../../tools/reference_remapper'

module Locomotive::Wagon

  # Rewrites stale references (old instance ids -> new ids) after a migrated site is
  # pushed. Mapping is keyed the way the push matches entities: pages by fullpath/handle,
  # entries by slug.
  class PushRemapReferencesCommand < PushBaseCommand

    OBJECT_ID_REGEXP = /\A[0-9a-f]{24}\z/i

    # the resources actually pushed (options[:resources]); nil/blank means all of them
    def for_resources(resources)
      @resources = resources
    end

    def push
      # Reference remap is data-only; require -d.
      return unless remappable_resources?

      # a regular (non-migrated) deploy carries no old ids: stay a strict no-op
      return if reference_mapping.empty?

      super
    end

    def _push
      instrument 'remap_started', count: reference_mapping.size, edited: remote_site.edited?

      # the decorators below re-run asset replacement to reproduce the exact pushed body.
      # they share the push's content_assets_pusher: every asset is already cached with
      # its checksum (same MD5 as the engine), so persist matches and makes no API call.
      remap_site
      remap_pages
      remap_content_entries
    end

    private

    def remap_site
      return unless with_data? && resource?('site')

      decorated = UpdateSiteDecorator.new(current_site, default_locale, path, content_assets_pusher)

      locales.each do |locale|
        original = decorated.__with_locale__(locale) { decorated.sections_content }
        next if original.nil?

        remapped = remapper.remap(original)
        next if remapped == original

        persist_with_log("site sections_content (#{locale})") do
          if locale.to_s == default_locale.to_s
            api_client.current_site.update(sections_content: remapped)
          else
            api_client.current_site.update({ sections_content: remapped }, locale)
          end
        end
      end
    end

    def remap_pages
      return unless resource?('pages')

      # the same back-office protection as the pages push itself (persist_content)
      unless with_data? || !remote_site.edited?
        instrument :warning, message: 'Back-office content protected — internal references in pages were NOT updated. Run with -d to overwrite.'
        return
      end

      repositories.page.all.each do |page|
        # scope = pages actually pushed this run: a page skipped by --resources or
        # --filter was never persisted, so it carries no remote_id and is left alone
        remote_id = page[:remote_id]
        next if remote_id.nil?

        decorated = PageDecorator.new(page, default_locale, content_assets_pusher, true)

        translated_in(decorated) do |locale|
          payload = remapped_page_payload(decorated)
          next if payload.empty?

          persist_with_log("page #{decorated.fullpath} (#{locale})") do
            api_client.pages.update(remote_id, payload, locale)
          end
        end
      end
    end

    def remapped_page_payload(decorated)
      {}.tap do |payload|
        %i(sections_content sections_dropzone_content).each do |name|
          original = decorated.public_send(name)
          next if original.nil?

          remapped = remapper.remap(original)
          payload[name] = remapped if remapped != original
        end

        elements = remapped_editable_elements(decorated)
        payload[:editable_elements] = elements unless elements.empty?
      end
    end

    # only the elements whose text content changed: the engine merges editable
    # elements by block+slug, so a subset update never deletes the others
    def remapped_editable_elements(decorated)
      (decorated.editable_elements || []).map do |element|
        hash    = element.to_hash
        content = hash[:content]
        next unless content.is_a?(String)

        remapped = remapper.remap(content)
        next if remapped == content

        hash.merge(content: remapped)
      end.compact
    end

    def remap_content_entries
      return unless with_data? && resource?('content_entries')

      repositories.content_type.all.each do |content_type|
        next if skip_content_type?(content_type)

        text_fields = content_type.fields.no_associations.select { |field| field.type == :text }
        next if text_fields.empty?

        repositories.content_entry.with(content_type).all(_visible: nil).each do |entry|
          remap_content_entry(entry, content_type, text_fields)
        end
      end
    end

    # mirrors PushContentEntriesCommand: --filter selects content types by slug, so a
    # filtered-out type must not be enumerated or remapped here either
    def skip_content_type?(content_type)
      return false if @only_entities.blank?

      !@only_entities.any? { |regexp| regexp.match(content_type.slug) }
    end

    def remap_content_entry(entry, content_type, text_fields)
      remote_id = entry[:remote_id]
      return if remote_id.nil?

      locales.each do |locale|
        default = locale.to_s == default_locale.to_s
        fields  = default ? text_fields : text_fields.select(&:localized?)
        next if fields.empty?

        decorated = ContentEntryDecorator.new(entry, locale, path, content_assets_pusher)
        payload   = remapped_entry_payload(decorated, fields)
        next if payload.empty?

        persist_with_log("#{content_type.slug} #{decorated._slug} (#{locale})") do
          api_client.content_entries(content_type).update(remote_id, payload, default ? nil : locale)
        end
      end
    end

    def remapped_entry_payload(decorated, fields)
      {}.tap do |payload|
        fields.each do |field|
          original = decorated.public_send(field.name)
          next unless original.is_a?(String)

          remapped = remapper.remap(original)
          payload[field.name.to_sym] = remapped if remapped != original
        end
      end
    end

    # old ids come from the data dir files (pages json "id", entries yaml "_id" array),
    # new ids were written to the memoized entities ([:remote_id]) by the push itself
    def reference_mapping
      @reference_mapping ||= {}.tap do |mapping|
        repositories.page.all.each do |page|
          record(mapping, page[:_id], page[:remote_id])
        end

        each_content_entry do |entry, _content_type|
          old_id = entry[:_id].is_a?(Array) ? entry[:_id].first : nil
          record(mapping, old_id, entry[:remote_id])
        end
      end
    end

    def record(mapping, old_id, new_id)
      return unless old_id.is_a?(String) && old_id =~ OBJECT_ID_REGEXP && !new_id.nil?

      old_id = old_id.downcase

      # already pointing at this instance (e.g. re-deploying data synced from it):
      # nothing to remap, and an identity entry would inflate the "remapping N" count
      return if old_id == new_id.to_s.downcase

      mapping[old_id] = new_id
    end

    def resource?(name)
      @resources.blank? || @resources.include?(name)
    end

    def remappable_resources?
      with_data? && (resource?('site') || resource?('pages') || resource?('content_entries'))
    end

    def each_content_entry(&block)
      repositories.content_type.all.each do |content_type|
        repositories.content_entry.with(content_type).all(_visible: nil).each do |entry|
          yield(entry, content_type)
        end
      end
    end

    def remapper
      @remapper ||= ReferenceRemapper.new(reference_mapping)
    end

    # mirrors PushBaseCommand#_push: a failed API update must log [failed], not stay
    # hanging on "persisting ..."
    def persist_with_log(label, &block)
      instrument :persist, label: label
      yield
      instrument :persist_with_success
    rescue Locomotive::Coal::ServerSideError => e
      instrument :persist_with_error, message: 'Locomotive Back-office error. Contact your administrator or check your application logs.'
      raise e
    rescue Exception => e
      instrument :persist_with_error, message: e.message
      raise e
    end

  end

end
