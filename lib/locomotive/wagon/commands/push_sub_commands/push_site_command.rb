module Locomotive::Wagon

  class PushSiteCommand < PushBaseCommand

    def entities
      [repositories.site.first]
    end

    def decorate(entity)
      UpdateSiteDecorator.new(entity, default_locale, path, content_assets_pusher)
    end

    def persist(decorated_entity)
      _attributes = decorated_entity.to_hash

      # push the picture only if there is no existing remote picture
      _attributes.delete(:picture) if remote_site['picture_url'].present?

      # timezone can be pushed with the -d option
      _attributes.delete(:timezone) unless with_data?

      # push the locales as long as there is no content on the remote site yet
      _attributes.delete(:locales) if remote_site.edited?

      _attributes.delete(:metafields) unless with_data?

      _attributes.delete(:sections_content) unless with_data?

      if _attributes.present?
        api_client.current_site.update(_attributes)

        # sections_content is not a `localized: true` attribute in the engine SiteForm,
        # so the update above only writes it to the default locale. Push the remaining
        # locales explicitly (symmetric with PullSiteCommand#add_other_locale).
        if with_data?
          (locales - [default_locale]).each do |locale|
            content = decorated_entity.__with_locale__(locale) do
              decorated_entity.sections_content
            end
            api_client.current_site.update({ sections_content: content }, locale) if content.present?
          end
        end
      else
        raise SkipPersistingException.new
      end
    end

    def label_for(decorated_entity)
      decorated_entity.name
    end

  end

end
