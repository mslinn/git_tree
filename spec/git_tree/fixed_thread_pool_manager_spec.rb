require 'spec_helper'
require_relative '../../lib/util/thread_pool_manager'
require_relative '../../lib/util/log'

describe FixedThreadPoolManager do
  describe 'initialization with quiet verbosity' do
    before do
      # Store original verbosity and set it to QUIET for this test
      @original_verbosity = Logging.verbosity
      Logging.verbosity = Logging::QUIET

      # Spy on the log method to capture any output
      allow(Logging).to receive(:log)
    end

    after do
      # Restore original verbosity
      Logging.verbosity = @original_verbosity
    end

    it 'does not log initialization messages' do
      described_class.new
      expect(Logging).not_to have_received(:log).with(Logging::DEBUG, /Initializing \d+ worker threads.../, :green)
    end
  end
end
