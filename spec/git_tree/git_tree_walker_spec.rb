require 'spec_helper'
require_relative '../../lib/util/git_tree_walker'
require_relative '../../lib/util/config'

describe GitTreeWalker do
  describe '#initialize and #determine_roots' do
    let(:mock_config) { instance_double(GitTree::GTConfig) }

    before do
      # Stub the config loader to isolate the walker
      allow(GitTree::GTConfig).to receive(:new).and_return(mock_config)
    end

    context 'when no command-line arguments are given' do
      it 'correctly uses and expands default_roots from the configuration' do
        # ARRANGE: Define the exact configuration and environment for this test.
        # This simulates the test environment's config file.
        test_default_roots = ['$TEST_WORK', '$TEST_SITES']
        allow(mock_config).to receive(:default_roots).and_return(test_default_roots)

        # This simulates the environment variables set by the integration test.
        allow(ENV).to receive(:fetch).with('TEST_WORK', nil).and_return('/tmp/test/work')
        allow(ENV).to receive(:fetch).with('TEST_SITES', nil).and_return('/tmp/test/sites')

        # ACT: Instantiate the walker. This triggers the `determine_roots` logic.
        walker = described_class.new([]) # Pass empty args to simulate default behavior

        # ASSERT: Verify the internal state with hard data.
        # This is the data we expect `determine_roots` to produce.
        expected_root_map = {
          '$TEST_WORK'  => [File.expand_path('/tmp/test/work')],
          '$TEST_SITES' => [File.expand_path('/tmp/test/sites')],
        }
        actual_root_map = walker.root_map

        # Compare the actual result with the expected data.
        # If this fails, the error message will show the exact discrepancy.
        expect(actual_root_map).to eq(expected_root_map),
                                   "Expected root_map to be #{expected_root_map}, but got #{actual_root_map}"

        expected_display_roots = ['$TEST_WORK', '$TEST_SITES']
        actual_display_roots = walker.display_roots

        expect(actual_display_roots).to match_array(expected_display_roots),
                                        "Expected display_roots to be #{expected_display_roots}, but got #{actual_display_roots}"
      end
    end
  end
end
