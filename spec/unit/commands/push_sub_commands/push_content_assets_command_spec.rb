# encoding: utf-8

require 'spec_helper'

require 'locomotive/wagon/commands/push_sub_commands/push_base_command'
require 'locomotive/wagon/commands/push_sub_commands/push_content_assets_command'

describe Locomotive::Wagon::PushContentAssetsCommand do

  let(:assets_api) { double('ContentAssetsAPI') }
  let(:api_client) { double('ApiClient', content_assets: assets_api) }
  let(:command)    { described_class.new(api_client, nil) }

  let(:decorated)  { double('ContentAssetDecorator', filename: 'logo.png', checksum: 'NEW', to_hash: { source: :io }) }
  let(:cached)     { double('RemoteAsset', _id: 'a1', checksum: 'OLD', url: '/old.png') }
  let(:updated)    { double('RemoteAsset', _id: 'a1', checksum: 'NEW', url: '/new.png') }

  before do
    allow(command).to receive(:decorate).and_return(decorated)
    allow(command).to receive(:remote_entities).and_return('logo.png' => cached)
  end

  describe '#persist of a changed, already-remote asset' do

    it 'updates it once, then serves later calls from the refreshed cache (no redundant update)' do
      expect(assets_api).to receive(:update).with('a1', { source: :io }).once.and_return(updated)

      command.persist('logo.png') # OLD != NEW -> update, cache now holds the NEW-checksum entity
      command.persist('logo.png') # NEW == NEW -> no second update (e.g. the remap pass)
    end

    it 'returns the updated url after the update' do
      allow(assets_api).to receive(:update).and_return(updated)

      expect(command.persist('logo.png')).to eq('/new.png')
    end

  end

  describe '#persist of an unchanged asset' do

    let(:decorated) { double('ContentAssetDecorator', filename: 'logo.png', checksum: 'OLD', to_hash: {}) }

    it 'does not update' do
      expect(assets_api).not_to receive(:update)

      expect(command.persist('logo.png')).to eq('/old.png')
    end

  end

end
