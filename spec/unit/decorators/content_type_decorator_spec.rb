# encoding: utf-8

require 'spec_helper'

require 'locomotive/wagon/decorators/concerns/to_hash_concern'
require 'locomotive/wagon/decorators/content_type_field_decorator'
require 'locomotive/wagon/decorators/content_type_decorator'

describe Locomotive::Wagon::ContentTypeDecorator do

  let(:option_0) { select_option({ en: 'alpha' }, 0) }
  let(:option_1) { select_option({ en: 'beta' }, 1) }

  let(:select_field) do
    double('ContentTypeField',
      name: 'category', label: nil, required: nil, localized: nil, unique: nil, default: nil,
      is_relationship?: false,
      select_options: double('SelectOptions', all: [option_0, option_1])
    ).tap do |f|
      allow(f).to receive(:[]).and_return(nil)
      allow(f).to receive(:[]).with(:type).and_return('select')
    end
  end

  let(:entity_fields) { double('Fields', no_associations: [select_field], associations: [], by_name: nil) }

  let(:entity) do
    double('ContentType', name: 'Updates', slug: 'updates', label_field_name: 'title', order_direction: nil, fields: entity_fields).tap do |e|
      allow(e).to receive(:[]).and_return(nil)
    end
  end

  let(:decorator) { described_class.new(entity) }

  describe '#to_hash' do

    subject(:payload) { decorator.to_hash }

    it 'carries select_options with their positions through the fields payload' do
      field = payload[:fields].first

      expect(field[:type]).to eq('select')
      expect(field[:select_options]).to eq([
        { name: { en: 'alpha' }, position: 0 },
        { name: { en: 'beta' },  position: 1 }
      ])
    end

  end

  def select_option(translations, position)
    name = double('I18nField', translations: translations)
    double('SelectOption', name: name).tap do |option|
      allow(option).to receive(:[]).with(:position).and_return(position)
    end
  end

end
