# encoding: utf-8

require 'spec_helper'

require 'active_support/notifications'
require 'colorize'

require_relative '../../../../lib/locomotive/wagon/commands/loggers/sync_logger'

describe Locomotive::Wagon::SyncLogger do

  def fire
    ActiveSupport::Notifications.instrument('wagon.sync.start', name: 'site')
  end

  it 'logs an event once per attached logger' do
    logger = described_class.new
    expect { fire }.to output(/Syncing Site/).to_stdout
    logger.detach
  end

  it 'stops logging after #detach (no duplicate output across runs)' do
    described_class.new.detach
    expect { fire }.not_to output.to_stdout
  end

  it 'does not double-log when a previous logger was detached' do
    described_class.new.detach   # a previous command's logger, cleaned up
    logger = described_class.new # the current command's logger

    output = capture_stdout { fire }
    expect(output.scan('Syncing Site').size).to eq(1)

    logger.detach
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

end
