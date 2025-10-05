require 'spec_helper'
require_relative '../../lib/util/thread_pool_manager'
require_relative '../../lib/util/log'

describe FixedThreadPoolManager do
  describe 'initialization with quiet verbosity' do
    before do
      # Store original verbosity and set it to QUIET for this test
      @original_verbosity = Logging.verbosity
      Logging.verbosity = Logging::QUIET

      # Spy on the `warn` method to capture any output to STDERR
      allow($stderr).to receive(:puts)
    end

    after do
      # Restore original verbosity
      Logging.verbosity = @original_verbosity # rubocop:disable RSpec/InstanceVariable
    end

    it 'does not log initialization messages' do
      described_class.new
      expect($stderr).not_to have_received(:puts).with(/Initializing \d+ worker threads.../)
    end
  end
end
