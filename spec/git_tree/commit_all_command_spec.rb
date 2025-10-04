require 'spec_helper'
require_relative '../../lib/commands/git_commit_all'
require_relative '../../lib/util/log'

describe GitTree::CommitAllCommand do
  include Logging

  subject(:command) { described_class.new(args, options: options) }

  let(:args) { ['/fake/root'] }
  let(:mock_walker) { instance_double(GitTreeWalker, process: nil) }
  let(:options) { { walker: mock_walker } }

  before do
    allow(command).to receive(:log)
    allow(Logging).to receive(:verbosity).and_return(Logging::NORMAL)
  end

  describe '#run' do
    it 'initializes the GitTreeWalker after parsing options' do
      # This test ensures that the walker is created with the final, parsed arguments
      # and options, not the initial ones, which was a source of a previous bug.
      command = described_class.new(['-v', '-m', 'test message', '/some/dir'])
      allow(GitTreeWalker).to receive(:new).and_return(mock_walker)

      command.run

      # It should be called with the arguments left *after* option parsing.
      expect(GitTreeWalker).to have_received(:new)
        .with(['/some/dir'], options: a_hash_including(message: 'test message', verbose: 2, serial: false))
    end
  end
end
