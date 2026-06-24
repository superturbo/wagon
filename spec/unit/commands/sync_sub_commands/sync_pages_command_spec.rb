# encoding: utf-8

require 'spec_helper'
require 'tmpdir'

require 'locomotive/coal/resource'
require 'locomotive/wagon/commands/pull_sub_commands/pull_base_command'
require 'locomotive/wagon/commands/pull_sub_commands/pull_pages_command'
require 'locomotive/wagon/commands/sync_sub_commands/concerns/base_concern'
require 'locomotive/wagon/commands/sync_sub_commands/sync_pages_command'

RSpec.describe Locomotive::Wagon::SyncPagesCommand do

  let(:site)    { instance_double('Site', locales: ['en']) }
  let(:command) { described_class.new(nil, site, path, 'test') }
  let(:path)    { Dir.mktmpdir }

  after { FileUtils.rm_rf(path) }

  describe '#write_page' do

    let(:page_id) { 'abc123' }
    let(:page_attributes) do
      {
        '_id'               => page_id,
        'title'             => 'Home',
        'slug'              => 'index',
        'handle'            => 'home',
        'listed'            => true,
        'published'         => true,
        'position'          => 0,
        'fullpath'          => 'index',
        'redirect_url'      => '',
        'editable_elements' => [],
        'seo_title'         => nil,
        'meta_description'  => nil,
        'meta_keywords'     => nil,
        'template'          => ''
      }
    end
    let(:page) { Locomotive::Coal::Resource.new(page_attributes) }

    before { command.instance_variable_set(:@fullpaths, page_id => 'index') }

    it 'defaults omitted section attributes for old engines' do
      expect(page).not_to respond_to(:sections_content)
      expect(page).not_to respond_to(:sections_dropzone_content)

      command.write_page(page, 'en')

      expect(written_page.fetch('sections_content')).to eq({})
      expect(written_page.fetch('sections_dropzone_content')).to eq([])
    end

    it 'parses section attributes when present' do
      page_attributes['sections_content'] = '{"hero":{"settings":{"title":"Hi"}}}'
      page_attributes['sections_dropzone_content'] = '[{"id":"hero"}]'

      command.write_page(page, 'en')

      expect(written_page.fetch('sections_content')).to eq('hero' => { 'settings' => { 'title' => 'Hi' } })
      expect(written_page.fetch('sections_dropzone_content')).to eq([{ 'id' => 'hero' }])
    end

    def written_page
      JSON.parse(File.read(File.join(path, 'data', 'test', 'pages', 'en', 'index.json')))
    end

  end

end
