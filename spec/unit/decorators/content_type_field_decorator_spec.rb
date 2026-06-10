# encoding: utf-8

require 'spec_helper'

require 'locomotive/wagon/decorators/concerns/to_hash_concern'
require 'locomotive/wagon/decorators/content_type_field_decorator'

describe Locomotive::Wagon::ContentTypeFieldDecorator do

  let(:field)          { double('Field', select_options: select_options) }
  let(:select_options) { double('SelectOptions', all: [first_option, second_option, third_option]) }
  let(:first_option)   { select_option({ en: 'alpha' }, 0) }
  let(:second_option)  { select_option({ en: 'beta' }, 1) }
  let(:third_option)   { select_option({ en: 'gamma' }, 2) }
  let(:decorator)      { described_class.new(field) }

  before do
    allow(field).to receive(:[]).with(:type).and_return('select')
  end

  describe '#select_options' do

    subject(:options) { decorator.select_options.map(&:to_hash) }

    it 'keeps positions when pushing select field options' do
      expect(options).to eq([
        { name: { en: 'alpha' }, position: 0 },
        { name: { en: 'beta' }, position: 1 },
        { name: { en: 'gamma' }, position: 2 }
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
