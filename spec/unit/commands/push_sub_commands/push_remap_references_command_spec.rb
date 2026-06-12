# encoding: utf-8

require 'spec_helper'

require 'locomotive/wagon/decorators/concerns/to_hash_concern'
require 'locomotive/wagon/decorators/concerns/persist_assets_concern'
require 'locomotive/steam/decorators/i18n_decorator'
require 'locomotive/steam/decorators/template_decorator'
require 'locomotive/wagon/decorators/site_decorator'
require 'locomotive/wagon/decorators/page_decorator'
require 'locomotive/wagon/decorators/content_entry_decorator'
require 'locomotive/wagon/tools/glob'
require 'locomotive/wagon/commands/push_sub_commands/push_base_command'
require 'locomotive/wagon/commands/push_sub_commands/push_remap_references_command'

describe Locomotive::Wagon::PushRemapReferencesCommand do

  let(:old_page_id)  { '656b3de3cb29bcc42bb756db' }
  let(:new_page_id)  { '6a29d363e366024051a34712' }
  let(:old_entry_id) { '5f0c1a2b3c4d5e6f70819203' }
  let(:new_entry_id) { '6b3a4c5d6e7f809102a3b4c5' }

  let(:pages)           { [] }
  let(:content_types)   { [] }
  let(:entries_by_type) { {} }

  let(:page_repository)          { double('PageRepository', all: pages) }
  let(:content_type_repository)  { double('ContentTypeRepository', all: content_types) }
  let(:content_entry_repository) { double('ContentEntryRepository') }
  let(:repositories) do
    double('Repositories',
      page:          page_repository,
      content_type:  content_type_repository,
      content_entry: content_entry_repository)
  end

  let(:site)           { instance_double('Site', default_locale: :en, locales: [:en], timezone: nil) }
  let(:steam_services) { double('SteamServices', repositories: repositories, current_site: site, locale: :en) }
  let(:api_client)     { double('ApiClient') }
  let(:remote_site)    { instance_double('RemoteSite', edited?: false) }
  let(:command)        { described_class.new(api_client, steam_services, nil, remote_site) }

  def page_double(_id, remote_id)
    double('Page').tap do |page|
      allow(page).to receive(:[]).with(:_id).and_return(_id)
      allow(page).to receive(:[]).with(:remote_id).and_return(remote_id)
    end
  end

  def entry_double(_id, remote_id)
    double('ContentEntry').tap do |entry|
      allow(entry).to receive(:[]).with(:_id).and_return(_id)
      allow(entry).to receive(:[]).with(:remote_id).and_return(remote_id)
    end
  end

  before do
    allow(content_entry_repository).to receive(:with) do |content_type|
      double('ScopedRepository', all: entries_by_type.fetch(content_type, []))
    end
  end

  describe '#reference_mapping' do

    subject(:mapping) { command.send(:reference_mapping) }

    context 'a synced page (hex id from the data dir) that was pushed' do
      let(:pages) { [page_double(old_page_id, new_page_id)] }
      it { is_expected.to eq({ old_page_id => new_page_id }) }
    end

    context 'a page never synced (integer id from the memory dataset)' do
      let(:pages) { [page_double(42, new_page_id)] }
      it { is_expected.to eq({}) }
    end

    context 'a synced page that was not pushed (no remote id)' do
      let(:pages) { [page_double(old_page_id, nil)] }
      it { is_expected.to eq({}) }
    end

    context 'a synced content entry (id + slug array) that was pushed' do
      let(:content_type)    { double('ContentType') }
      let(:content_types)   { [content_type] }
      let(:entries_by_type) { { content_type => [entry_double([old_entry_id, 'apple'], new_entry_id)] } }

      it { is_expected.to eq({ old_entry_id => new_entry_id }) }
    end

    context 'a local-only content entry (slug as id)' do
      let(:content_type)    { double('ContentType') }
      let(:content_types)   { [content_type] }
      let(:entries_by_type) { { content_type => [entry_double('apple', new_entry_id)] } }

      it { is_expected.to eq({}) }
    end

  end

  describe '#push with an empty mapping (a regular, non-migrated deploy)' do

    it 'does nothing: no notifications, no API calls' do
      expect(command).not_to receive(:_push_with_timezone)
      expect(ActiveSupport::Notifications).not_to receive(:instrument)

      command.push
    end

  end

  describe '#remap_site' do

    let(:site)             { instance_double('Site', default_locale: :en, locales: [:en, :fr, :es], timezone: nil) }
    let(:pages)            { [page_double(old_page_id, new_page_id)] }
    let(:current_site_api) { double('CurrentSiteAPI') }
    let(:sections_by_locale) do
      {
        en: %({"link":{"type":"page","value":"#{old_page_id}"}}),
        fr: %({"link":{"type":"page","value":"#{new_page_id}"}}), # already correct -> no update
        es: nil                                                   # locale without sections
      }
    end
    let(:decorated_site) { double('UpdateSiteDecorator') }

    before do
      allow(api_client).to receive(:current_site).and_return(current_site_api)
      allow(current_site_api).to receive(:update)
      allow(command).to receive(:path).and_return('.')

      allow(Locomotive::Wagon::UpdateSiteDecorator).to receive(:new).and_return(decorated_site)
      allow(decorated_site).to receive(:__with_locale__) do |locale, &block|
        allow(decorated_site).to receive(:sections_content).and_return(sections_by_locale[locale])
        block.call
      end
    end

    context 'with data (-d)' do

      before do
        command.with_data
        command.send(:remap_site)
      end

      it 'updates the default locale without a locale argument' do
        expect(current_site_api).to have_received(:update)
          .with(sections_content: sections_by_locale[:en].gsub(old_page_id, new_page_id)).once
      end

      it 'does not update a locale whose content has no stale ids' do
        expect(current_site_api).not_to have_received(:update).with(anything, :fr)
      end

      it 'skips a locale without sections content' do
        expect(current_site_api).not_to have_received(:update).with(anything, :es)
      end

    end

    context 'without data' do

      it 'does not touch the site' do
        command.send(:remap_site)
        expect(current_site_api).not_to have_received(:update)
      end

    end

  end

  describe '#remap_pages' do

    let(:page)      { page_double(old_page_id, page_remote_id) }
    let(:pages)     { [page] }
    let(:pages_api) { double('PagesAPI', update: nil) }

    let(:page_remote_id)    { new_page_id }
    let(:sections)          { %({"link":{"type":"page","value":"#{old_page_id}"}}) }
    let(:dropzone)          { %([{"type":"banner"}]) } # no stale ids -> must not be sent
    let(:editable_elements) do
      [
        element_double(block: 'main', slug: 'body', content: %(<a href="x">#{old_page_id}</a>)),
        element_double(block: 'main', slug: 'icon', content: double('UploadIO'))
      ]
    end

    let(:decorated_page) { double('PageDecorator', fullpath: 'index') }

    def element_double(hash)
      double('EditableElementDecorator', to_hash: hash)
    end

    before do
      allow(api_client).to receive(:pages).and_return(pages_api)
      allow(command).to receive(:path).and_return('.')

      allow(Locomotive::Wagon::PageDecorator).to receive(:new).and_return(decorated_page)
      allow(decorated_page).to receive(:__with_locale__) { |_locale, &block| block.call }
      allow(decorated_page).to receive(:slug).and_return('index')
      allow(decorated_page).to receive(:sections_content).and_return(sections)
      allow(decorated_page).to receive(:sections_dropzone_content).and_return(dropzone)
      allow(decorated_page).to receive(:editable_elements).and_return(editable_elements)
    end

    context 'on a fresh site' do

      before { command.send(:remap_pages) }

      it 'updates the page with only the changed keys' do
        expect(pages_api).to have_received(:update).with(
          new_page_id,
          {
            sections_content:  sections.gsub(old_page_id, new_page_id),
            editable_elements: [{ block: 'main', slug: 'body', content: %(<a href="x">#{new_page_id}</a>) }]
          },
          :en
        )
      end

      context 'when nothing references a stale id' do
        let(:sections)          { %({"link":{"type":"page","value":"#{new_page_id}"}}) }
        let(:editable_elements) { [] }

        it 'does not update the page' do
          expect(pages_api).not_to have_received(:update)
        end
      end

      context 'a page that was not pushed' do
        let(:page_remote_id) { nil }

        it 'is skipped' do
          expect(pages_api).not_to have_received(:update)
        end
      end

    end

    context 'on an edited site without -d (back-office protection)' do

      let(:remote_site) { instance_double('RemoteSite', edited?: true) }

      it 'does not touch any page and warns about the protection' do
        expect(command).to receive(:instrument)
          .with(:warning, message: a_string_matching(/back-office/i))

        command.send(:remap_pages)
        expect(pages_api).not_to have_received(:update)
      end

    end

    context 'a selective push that excludes pages (--resources content_entries)' do

      before do
        command.with_data
        command.for_resources(%w(content_entries))
      end

      it 'does not touch the pages' do
        command.send(:remap_pages)
        expect(pages_api).not_to have_received(:update)
      end

    end

    context 'a page excluded by --filter (filtered out, so never pushed)' do

      # a page skipped by --filter is not persisted, so it carries no remote_id;
      # remap_pages scopes to the pages actually pushed this run
      let(:page_remote_id) { nil }

      before do
        command.with_data
        command.only(['some-other-page'])
      end

      it 'is not remapped' do
        command.send(:remap_pages)
        expect(pages_api).not_to have_received(:update)
      end

    end

  end

  describe 'asset handling' do

    let(:pusher)         { double('ContentAssetsPusher') }
    let(:command)        { described_class.new(api_client, steam_services, pusher, remote_site) }
    let(:pages)          { [page_double(old_page_id, new_page_id)] }
    let(:pages_api)      { double('PagesAPI', update: nil) }
    let(:decorated_page) do
      double('PageDecorator', fullpath: 'index', slug: 'index',
        sections_content: nil, sections_dropzone_content: nil, editable_elements: [])
    end

    before do
      allow(api_client).to receive(:pages).and_return(pages_api)
      allow(command).to receive(:path).and_return('.')
      allow(decorated_page).to receive(:__with_locale__) { |_locale, &block| block.call }
      command.with_data
    end

    # the decorators reuse the push's pusher (its cache prevents re-creating assets);
    # this only pins the reuse, not the pusher's own dedup behaviour
    it 'builds the decorators with the push content assets pusher' do
      captured = nil
      allow(Locomotive::Wagon::PageDecorator).to receive(:new) do |*args|
        captured = args[2]
        decorated_page
      end

      command.send(:remap_pages)

      expect(captured).to be(pusher)
    end

  end

  describe 'selective push protects the site (--resources content_entries)' do

    let(:pages)            { [page_double(old_page_id, new_page_id)] }
    let(:current_site_api) { double('CurrentSiteAPI', update: nil) }

    before do
      allow(api_client).to receive(:current_site).and_return(current_site_api)
      command.with_data
      command.for_resources(%w(content_entries))
    end

    it 'does not rewrite site.sections_content' do
      command.send(:remap_site)
      expect(current_site_api).not_to have_received(:update)
    end

  end

  describe 'a failing API update' do

    let(:pages)            { [page_double(old_page_id, new_page_id)] }
    let(:current_site_api) { double('CurrentSiteAPI') }
    let(:decorated_site)   { double('UpdateSiteDecorator') }

    before do
      allow(api_client).to receive(:current_site).and_return(current_site_api)
      allow(current_site_api).to receive(:update).and_raise(StandardError.new('boom'))
      allow(command).to receive(:path).and_return('.')
      allow(Locomotive::Wagon::UpdateSiteDecorator).to receive(:new).and_return(decorated_site)
      allow(decorated_site).to receive(:__with_locale__) do |_locale, &block|
        allow(decorated_site).to receive(:sections_content).and_return(%({"v":"#{old_page_id}"}))
        block.call
      end
      command.with_data
    end

    it 'logs a persist failure before re-raising' do
      expect(command).to receive(:instrument).with(:persist, anything)
      expect(command).to receive(:instrument).with(:persist_with_error, hash_including(:message))

      expect { command.send(:remap_site) }.to raise_error(StandardError, 'boom')
    end

  end

  describe '#_push announcement' do

    let(:pages) { [page_double(old_page_id, new_page_id)] }

    before do
      allow(command).to receive(:remap_site)
      allow(command).to receive(:remap_pages)
      allow(command).to receive(:remap_content_entries)
    end

    it 'announces the remapping with the number of stale ids and the site freshness' do
      expect(command).to receive(:instrument)
        .with('remap_started', count: 1, edited: false)

      command.send(:_push)
    end

  end

  describe '#remap_content_entries' do

    let(:site)  { instance_double('Site', default_locale: :en, locales: [:en, :fr], timezone: nil) }
    let(:pages) { [page_double(old_page_id, new_page_id)] } # puts the page pair into the mapping

    let(:body_field)  { double('Field', name: 'body',  type: :text,   localized?: true) }
    let(:notes_field) { double('Field', name: 'notes', type: :text,   localized?: false) }
    let(:title_field) { double('Field', name: 'title', type: :string, localized?: true) }
    let(:fields)      { double('Fields', no_associations: [body_field, notes_field, title_field]) }

    let(:content_type)    { double('ContentType', slug: 'articles', fields: fields) }
    let(:content_types)   { [content_type] }
    let(:entry)           { entry_double([old_entry_id, 'apple'], new_entry_id) }
    let(:entries_by_type) { { content_type => [entry] } }

    let(:values_by_locale) do
      {
        en: { 'body' => "see #{old_page_id}", 'notes' => 'plain notes' },
        fr: { 'body' => "voir #{old_page_id}" }
      }
    end

    let(:entries_api)     { double('ContentEntriesAPI', update: nil) }
    let(:decorated_entry) { double('ContentEntryDecorator', _slug: 'apple') }

    before do
      allow(api_client).to receive(:content_entries).with(content_type).and_return(entries_api)
      allow(command).to receive(:path).and_return('.')

      allow(Locomotive::Wagon::ContentEntryDecorator).to receive(:new) do |_entity, locale, *|
        allow(decorated_entry).to receive(:body).and_return(values_by_locale[locale]['body'])
        allow(decorated_entry).to receive(:notes).and_return(values_by_locale[locale]['notes'])
        decorated_entry
      end
    end

    context 'with data (-d)' do

      before do
        command.with_data
        command.send(:remap_content_entries)
      end

      it 'updates the default locale text fields without a locale argument' do
        expect(entries_api).to have_received(:update)
          .with(new_entry_id, { body: "see #{new_page_id}" }, nil)
      end

      it 'updates only localized text fields for the other locales' do
        expect(entries_api).to have_received(:update)
          .with(new_entry_id, { body: "voir #{new_page_id}" }, :fr)
      end

      context 'when no text field carries a stale id' do
        let(:values_by_locale) do
          { en: { 'body' => 'clean', 'notes' => 'clean' }, fr: { 'body' => 'propre' } }
        end

        it 'does not update the entry' do
          expect(entries_api).not_to have_received(:update)
        end
      end

      context 'a content type without text fields' do
        let(:fields) { double('Fields', no_associations: [title_field]) }

        it 'is not updated' do
          expect(entries_api).not_to have_received(:update)
        end
      end

    end

    context 'with data (-d) but a --filter that excludes this content type' do

      it 'does not enumerate or update the filtered-out content type' do
        command.with_data
        command.only(['other-type'])
        command.send(:remap_content_entries)

        expect(entries_api).not_to have_received(:update)
      end

    end

    context 'without data' do

      it 'does not touch any entry' do
        command.send(:remap_content_entries)
        expect(entries_api).not_to have_received(:update)
      end

    end

  end

end
