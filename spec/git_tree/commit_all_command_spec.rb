require 'spec_helper'
require_relative '../../lib/commands/git_commit_all'
require_relative '../../lib/util/log'

describe GitTree::CommitAllCommand do
  subject(:command) { described_class.new(args) }

  include Logging

  let(:mock_walker) { instance_double(GitTreeWalker) }

  before do
    # This is a simplified test focusing on argument parsing and walker interaction
    allow(GitTreeWalker).to receive(:new).and_return(mock_walker)
    allow(mock_walker).to receive(:process)
  end

  describe '#run' do
    context 'with a custom message' do
      let(:args) { ['-m', 'my test message'] }

      it 'initializes with the correct message option' do
        command.setup
        expect(command.instance_variable_get(:@options)[:message]).to eq('my test message')
      end

      it 'creates a walker and processes' do
        command.run
        expect(GitTreeWalker).to have_received(:new).with([], options: hash_including(message: 'my test message'))
        expect(mock_walker).to have_received(:process)
      end
    end
  end
end
