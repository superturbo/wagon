# encoding: utf-8

require 'spec_helper'

require 'json'
require 'base64'

require_relative '../../../lib/locomotive/wagon/tools/reference_remapper.rb'

describe Locomotive::Wagon::ReferenceRemapper do

  let(:old_page_id)   { '656b3de3cb29bcc42bb756db' }
  let(:new_page_id)   { '6a29d363e366024051a34712' }
  let(:old_entry_id)  { '5f0c1a2b3c4d5e6f70819203' }
  let(:new_entry_id)  { '6b3a4c5d6e7f809102a3b4c5' }
  let(:unknown_id)    { 'aaaaaaaaaaaaaaaaaaaaaaaa' }

  let(:mapping) do
    {
      old_page_id  => new_page_id,
      old_entry_id => new_entry_id
    }
  end

  let(:remapper) { described_class.new(mapping) }

  def encode_link(payload)
    Base64.strict_encode64(payload.to_json)
  end

  def decode_link(encoded)
    JSON.parse(Base64.decode64(encoded))
  end

  describe '#remap' do

    it 'replaces a mapped id inside a plain string' do
      expect(remapper.remap("the page is #{old_page_id} here")).to eq("the page is #{new_page_id} here")
    end

    it 'leaves an unknown 24-hex id untouched' do
      expect(remapper.remap("id #{unknown_id}")).to eq("id #{unknown_id}")
    end

    it 'matches an uppercase old id' do
      expect(remapper.remap(old_page_id.upcase)).to eq(new_page_id)
    end

    it 'remaps a page link setting' do
      setting = { 'type' => 'page', 'value' => old_page_id, 'new_window' => false }
      expect(remapper.remap(setting)).to eq({ 'type' => 'page', 'value' => new_page_id, 'new_window' => false })
    end

    it 'remaps both ids of a content_entry link setting' do
      setting = { 'type' => 'content_entry', 'value' => { 'page_id' => old_page_id, 'content_type_slug' => 'products', 'id' => old_entry_id } }
      expect(remapper.remap(setting)['value']).to eq({ 'page_id' => new_page_id, 'content_type_slug' => 'products', 'id' => new_entry_id })
    end

    it 'remaps a content entry picker setting inside an array of blocks' do
      blocks = [{ 'settings' => { 'article' => { 'id' => old_entry_id } } }]
      expect(remapper.remap(blocks)).to eq([{ 'settings' => { 'article' => { 'id' => new_entry_id } } }])
    end

    it 'remaps ids inside a JSON string (sections_content pushed as a string)' do
      json = { 'banner' => { 'settings' => { 'link' => { 'type' => 'page', 'value' => old_page_id } } } }.to_json
      expect(remapper.remap(json)).to eq(json.gsub(old_page_id, new_page_id))
    end

    it 'passes non-string scalars through' do
      expect(remapper.remap(42)).to eq(42)
      expect(remapper.remap(true)).to eq(true)
      expect(remapper.remap(nil)).to eq(nil)
    end

    it 'does not mutate the input' do
      setting = { 'value' => old_page_id.dup }
      remapper.remap(setting)
      expect(setting['value']).to eq(old_page_id)
    end

    describe 'encoded /_locomotive-link/ payloads' do

      let(:payload) { { 'type' => 'page', 'value' => old_page_id, 'locale' => 'en', 'new_window' => false } }
      let(:html)    { %(<p>intro</p><a href="https://host/_locomotive-link/#{encode_link(payload)}">link</a>) }

      it 'remaps the id inside the encoded payload and keeps the surrounding html' do
        remapped = remapper.remap(html)

        encoded = remapped[%r{/_locomotive-link/([A-Za-z0-9+/=]+)}, 1]
        expect(decode_link(encoded)['value']).to eq(new_page_id)
        expect(remapped).to start_with('<p>intro</p><a href="https://host/_locomotive-link/')
        expect(remapped).to end_with('">link</a>')
      end

      it 'keeps a payload without mapped ids byte-identical' do
        no_match = %(<a href="/_locomotive-link/#{encode_link({ 'type' => 'page', 'value' => unknown_id })}">x</a>)
        expect(remapper.remap(no_match)).to eq(no_match)
      end

      it 'leaves an invalid payload untouched' do
        broken = '<a href="/_locomotive-link/not-base64!">x</a>'
        expect(remapper.remap(broken)).to eq(broken)
      end

      it 'leaves a non-JSON base64 payload untouched' do
        non_json = %(<a href="/_locomotive-link/#{Base64.strict_encode64('plain text')}">x</a>)
        expect(remapper.remap(non_json)).to eq(non_json)
      end

      it 'is idempotent' do
        once  = remapper.remap(html)
        twice = remapper.remap(once)
        expect(twice).to eq(once)
      end

      it 'handles a string mixing an encoded link and a raw id' do
        mixed    = %(see #{old_entry_id} and <a href="/_locomotive-link/#{encode_link(payload)}">link</a>)
        remapped = remapper.remap(mixed)

        expect(remapped).to include(new_entry_id)
        encoded = remapped[%r{/_locomotive-link/([A-Za-z0-9+/=]+)}, 1]
        expect(decode_link(encoded)['value']).to eq(new_page_id)
      end

    end

  end

end
