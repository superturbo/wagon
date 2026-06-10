# encoding: utf-8

require 'spec_helper'

require 'active_support'
require 'active_support/core_ext'
require 'locomotive/wagon/commands/pull_sub_commands/pull_base_command'
require 'locomotive/wagon/commands/pull_sub_commands/pull_content_entries_command'

describe Locomotive::Wagon::PullContentEntriesCommand do

  let(:locales)    { ['en'] }
  let(:site)       { instance_double('Site', locales: locales) }
  let(:api_client) { double('api_client') }
  let(:command)    { described_class.new(api_client, site, nil, 'production') }

  def entries_result(entries, next_page: nil)
    entries.tap do |result|
      allow(result).to receive(:_next_page).and_return(next_page)
    end
  end

  def entry(id)
    instance_double('ContentEntry', _id: id)
  end

  describe '#content_entries_order_by' do

    subject { command.send(:content_entries_order_by, content_type) }

    def content_type_with(order_by:, order_direction:)
      instance_double('ContentType', attributes: { 'order_by' => order_by, 'order_direction' => order_direction })
    end

    context 'manually ordered content type' do
      let(:content_type) { content_type_with(order_by: '_position', order_direction: 'asc') }
      it { is_expected.to eq('_position asc') }
    end

    context 'date ordered content type' do
      let(:content_type) { content_type_with(order_by: 'created_at', order_direction: 'desc') }
      it { is_expected.to eq('created_at desc') }
    end

    context 'custom field ordering' do
      let(:content_type) { content_type_with(order_by: 'name', order_direction: 'asc') }
      it { is_expected.to eq('name asc') }
    end

    context 'missing order settings' do
      let(:content_type) { content_type_with(order_by: nil, order_direction: nil) }
      it { is_expected.to eq('created_at asc') }
    end

  end

  describe '#fetch_content_entries' do

    let(:localized_names) { [] }

    let(:content_type) do
      instance_double(
        'ContentType',
        attributes: { 'order_by' => '_position', 'order_direction' => 'asc', 'localized_names' => localized_names }
      )
    end

    let(:entries_resource) { double('content_entries_resource') }
    let(:result)           { entries_result([]) }

    before do
      allow(api_client).to receive(:content_entries).with(content_type).and_return(entries_resource)
    end

    it 'fetches entries using the content type order settings' do
      expect(entries_resource).to receive(:all)
        .with(nil, { page: 1, order_by: '_position asc' }, 'en')
        .and_return(result)

      command.send(:fetch_content_entries, content_type) { |entries| entries }
    end

    context 'with a localized order field' do

      let(:locales) { ['en', 'fr'] }
      let(:localized_names) { ['title'] }
      let(:content_type) do
        instance_double(
          'ContentType',
          attributes: { 'order_by' => 'title', 'order_direction' => 'asc', 'localized_names' => localized_names }
        )
      end

      let(:en_entry_1) { entry('1') }
      let(:en_entry_2) { entry('2') }
      let(:fr_entry_1) { entry('1') }
      let(:fr_entry_2) { entry('2') }

      it 'paginates by the default locale and merges translations by id' do
        expect(entries_resource).to receive(:all)
          .with(nil, { page: 1, order_by: 'title asc' }, 'en')
          .ordered
          .and_return(entries_result([en_entry_1, en_entry_2]))

        expect(entries_resource).to receive(:all)
          .with({ '_id' => { '$in' => ['1', '2'] } }, { page: 1, per_page: 2 }, 'fr')
          .ordered
          .and_return(entries_result([fr_entry_2, fr_entry_1]))

        yielded_entries = nil
        command.send(:fetch_content_entries, content_type) { |entries| yielded_entries = entries }

        expect(yielded_entries).to eq([
          { 'en' => en_entry_1, 'fr' => fr_entry_1 },
          { 'en' => en_entry_2, 'fr' => fr_entry_2 }
        ])
      end

      it 'leaves an entry untouched when its translation is missing' do
        expect(entries_resource).to receive(:all)
          .with(nil, { page: 1, order_by: 'title asc' }, 'en')
          .and_return(entries_result([en_entry_1, en_entry_2]))

        # only entry 1 exists in the fr locale
        expect(entries_resource).to receive(:all)
          .with({ '_id' => { '$in' => ['1', '2'] } }, { page: 1, per_page: 2 }, 'fr')
          .and_return(entries_result([fr_entry_1]))

        yielded_entries = nil
        command.send(:fetch_content_entries, content_type) { |entries| yielded_entries = entries }

        expect(yielded_entries).to eq([
          { 'en' => en_entry_1, 'fr' => fr_entry_1 },
          { 'en' => en_entry_2 }
        ])
      end

      it 'paginates the default locale and fetches translations per page' do
        en_entry_3 = entry('3')
        fr_entry_3 = entry('3')

        expect(entries_resource).to receive(:all)
          .with(nil, { page: 1, order_by: 'title asc' }, 'en')
          .and_return(entries_result([en_entry_1, en_entry_2], next_page: 2))
        expect(entries_resource).to receive(:all)
          .with({ '_id' => { '$in' => ['1', '2'] } }, { page: 1, per_page: 2 }, 'fr')
          .and_return(entries_result([fr_entry_1, fr_entry_2]))

        expect(entries_resource).to receive(:all)
          .with(nil, { page: 2, order_by: 'title asc' }, 'en')
          .and_return(entries_result([en_entry_3], next_page: nil))
        expect(entries_resource).to receive(:all)
          .with({ '_id' => { '$in' => ['3'] } }, { page: 1, per_page: 1 }, 'fr')
          .and_return(entries_result([fr_entry_3]))

        pages = []
        command.send(:fetch_content_entries, content_type) { |entries| pages << entries }

        expect(pages).to eq([
          [{ 'en' => en_entry_1, 'fr' => fr_entry_1 }, { 'en' => en_entry_2, 'fr' => fr_entry_2 }],
          [{ 'en' => en_entry_3, 'fr' => fr_entry_3 }]
        ])
      end

    end

    context 'on a multi-locale site ordered by a non-localized field' do

      let(:locales) { ['en', 'fr'] }
      let(:content_type) do
        instance_double(
          'ContentType',
          attributes: { 'order_by' => 'name', 'order_direction' => 'asc', 'localized_names' => ['title'] } # localized fields, but the order field is not the localized one
        )
      end

      let(:en_entry_1) { entry('1') }
      let(:en_entry_2) { entry('2') }
      let(:fr_entry_1) { entry('1') }
      let(:fr_entry_2) { entry('2') }

      it 'fetches the same page for each locale and merges by id' do
        expect(entries_resource).to receive(:all)
          .with(nil, { page: 1, order_by: 'name asc' }, 'en')
          .and_return(entries_result([en_entry_1, en_entry_2]))
        expect(entries_resource).to receive(:all)
          .with(nil, { page: 1, order_by: 'name asc' }, 'fr')
          .and_return(entries_result([fr_entry_1, fr_entry_2]))

        yielded_entries = nil
        command.send(:fetch_content_entries, content_type) { |entries| yielded_entries = entries }

        expect(yielded_entries).to eq([
          { 'en' => en_entry_1, 'fr' => fr_entry_1 },
          { 'en' => en_entry_2, 'fr' => fr_entry_2 }
        ])
      end

    end

  end

end
