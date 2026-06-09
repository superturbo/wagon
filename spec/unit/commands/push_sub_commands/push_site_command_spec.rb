# encoding: utf-8

require 'spec_helper'

require 'locomotive/wagon/commands/push_sub_commands/push_base_command'
require 'locomotive/wagon/commands/push_sub_commands/push_site_command'

describe Locomotive::Wagon::PushSiteCommand do

  # Principle: site sections_content is a per-locale value, but a single API update
  # only writes the default locale (the engine SiteForm does not treat it as a
  # localized attribute). So a data deploy must push sections_content for EVERY
  # non-default locale too — symmetric with the pull side, which fetches each locale.

  let(:site)             { instance_double('Site', default_locale: :en, locales: [:en, :fr, :es]) }
  let(:current_site_api) { instance_double('CurrentSiteAPI') }
  let(:api_client)       { instance_double('ApiClient', current_site: current_site_api) }
  let(:remote_site)      { instance_double('RemoteSite', edited?: false) }
  let(:command)          { described_class.new(api_client, nil, nil, remote_site) }

  let(:attributes)         { { name: 'Sample', sections_content: 'DEFAULT_JSON' } }
  let(:sections_by_locale) { { fr: 'FR_JSON', es: 'ES_JSON' } }
  let(:decorated_entity)   { instance_double('SiteDecorator', to_hash: attributes) }

  before do
    allow(command).to receive(:current_site).and_return(site)
    allow(remote_site).to receive(:[]).with('picture_url').and_return(nil)
    allow(current_site_api).to receive(:update)

    # Emulate the decorator: __with_locale__ scopes what sections_content returns.
    allow(decorated_entity).to receive(:__with_locale__) do |locale, &block|
      allow(decorated_entity).to receive(:sections_content).and_return(sections_by_locale[locale])
      block.call
    end
  end

  describe '#persist' do

    context 'deploying with data (-d)' do

      before do
        command.with_data
        command.persist(decorated_entity)
      end

      it 'pushes the default locale once with the full attributes' do
        expect(current_site_api).to have_received(:update).with(attributes).once
      end

      it 'pushes sections_content for each non-default locale, scoped to that locale' do
        expect(current_site_api).to have_received(:update).with({ sections_content: 'FR_JSON' }, :fr)
        expect(current_site_api).to have_received(:update).with({ sections_content: 'ES_JSON' }, :es)
      end

      it 'does not push a redundant locale-scoped update for the default locale' do
        expect(current_site_api).not_to have_received(:update).with(anything, :en)
      end

    end

    context 'deploying without data' do

      before { command.persist(decorated_entity) }

      it 'updates the site only once (default locale)' do
        expect(current_site_api).to have_received(:update).once
      end

      it 'never pushes a locale-scoped sections_content' do
        expect(current_site_api).not_to have_received(:update).with(anything, instance_of(Symbol))
      end

    end

    context 'when a non-default locale has no sections_content' do

      let(:sections_by_locale) { { fr: 'FR_JSON', es: nil } }

      before do
        command.with_data
        command.persist(decorated_entity)
      end

      it 'still pushes the locales that have content' do
        expect(current_site_api).to have_received(:update).with({ sections_content: 'FR_JSON' }, :fr)
      end

      it 'skips the locales without content' do
        expect(current_site_api).not_to have_received(:update).with(anything, :es)
      end

    end

  end

end
