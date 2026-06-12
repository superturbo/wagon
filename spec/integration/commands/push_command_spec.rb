# encoding: utf-8

require File.dirname(__FILE__) + '/../integration_helper'
require 'locomotive/wagon/commands/push_command'
require 'thor'

describe Locomotive::Wagon::PushCommand do

  # the stale page id carried in the migrated fixture (data/local + bands/updates)
  STALE_PAGE_ID = '656b3de3cb29bcc42bb756dc'.freeze

  # the single "type":"page" link value inside a captured sections_content payload
  def page_link_value(payload)
    payload[:sections_content].to_s[/"type":"page","value":"([0-9a-f]{24})"/, 1]
  end

  before { VCR.insert_cassette 'push' }
  after  { VCR.eject_cassette }

  let(:env)       { 'production' }
  let(:path)      { default_site_path }
  let(:shell)     { Thor::Shell::Color.new }
  let(:options)   { { data: true, verbose: true } }
  let(:command)   { described_class.new(env, path, options, shell) }

  describe '#push' do

    subject { command.push }

    context 'unknown env' do

      let(:credentials) { instance_double('Credentials', login: TEST_API_EMAIL, password: TEST_API_KEY) }
      let(:env) { 'hosting' }

      before do
        allow(command).to receive(:ask_for_performing).with('You are about to deploy a new site').and_return(true)
        allow(Netrc).to receive(:read).and_return(TEST_PLATFORM_ALT_URL => credentials)
        allow(command).to receive(:ask_for_performing).with("Warning! You're about to deploy data which will alter the content of your site.").and_return(true)
        allow(shell).to receive(:ask).with("What is the URL of your platform? (default: https://station.locomotive.works)").and_return(TEST_PLATFORM_URL)
        allow(shell).to receive(:ask).with('What is the handle of your site? (default: a random one)').and_return('wagon-test')
      end

      after { restore_deploy_file(default_site_path) }

      context 'answer yes to the deployment of the data' do

        before do
          allow(shell).to receive(:yes?).with("Are you sure you want to perform this action? (answer yes or no)").and_return(true)
        end

        it 'creates a site, pushes it and remaps the references carried over from the previous instance' do
          resources, remapped, page_updates, subscribers = [], [], [], []
          subscribers << ActiveSupport::Notifications.subscribe('wagon.push') do |name, start, finish, id, payload|
            resources << payload[:name]
          end
          subscribers << ActiveSupport::Notifications.subscribe('wagon.push.persist') do |name, start, finish, id, payload|
            remapped << payload[:label] if payload[:name] == 'remap_references'
          end

          # capture the actual page updates this run sends (not the static cassette):
          # a body regression would be caught here even if the cassette stayed stale
          allow_any_instance_of(Locomotive::Coal::Resources::Pages).to receive(:update).and_wrap_original do |original, *args|
            page_updates << { id: args[0], payload: args[1] }
            original.call(*args)
          end

          is_expected.not_to eq nil
          expect(resources).to eq %w(site content_types content_entries pages snippets sections theme_assets translations remap_references)
          expect(remapped).to include('page index (en)', 'updates update-number-6 (en)')

          # the index page links to itself; it is first pushed with the stale id, then the
          # remap re-pushes it pointing to the page's own NEW id (id arg == link value)
          initial = page_updates.find { |update| page_link_value(update[:payload]) == STALE_PAGE_ID }
          remap   = page_updates.find { |update| (value = page_link_value(update[:payload])) && value != STALE_PAGE_ID }

          expect(initial).not_to be_nil
          expect(remap).not_to be_nil
          expect(page_link_value(remap[:payload])).to eq(remap[:id])
        ensure
          subscribers.each { |subscriber| ActiveSupport::Notifications.unsubscribe(subscriber) }
        end

        context 'no previous authentication' do

          let(:credentials) { nil }

          it 'stops the deployment' do
            expect(shell).to receive(:say).with("Sorry, we were unable to find the credentials for this platform.\nPlease first login using the \"bundle exec wagon auth\"", :yellow)
            is_expected.to eq nil
          end

        end

      end

      context 'answer no to the deployment of the data' do

        before do
          allow(command).to receive(:ask_for_performing).with("Warning! You're about to deploy data which will alter the content of your site.").and_return(nil)
        end

        it "doesn't push the site" do
          resources = []
          subscriber = ActiveSupport::Notifications.subscribe('wagon.push') do |name, start, finish, id, payload|
            resources << payload[:name]
          end
          is_expected.to eq nil
          expect(resources).to eq([])
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end

      end

    end

  end

end
