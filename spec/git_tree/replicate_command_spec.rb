require '../spec_helper'
require_relative '../../lib/commands/git_replicate'
require_relative '../../lib/util/log'

describe GitTree::ReplicateCommand do
  subject(:command) { described_class.new(args) }

  include Logging

  let(:mock_walker) { instance_double(GitTreeWalker) }

  before do
    allow(GitTreeWalker).to receive(:new).and_return(mock_walker)
    allow(mock_walker).to receive(:find_and_process_repos)
    allow(command).to receive(:log_stdout)
  end

  describe '#run' do
    context 'with specified roots' do
      let(:args) { ['$work'] }

      it 'creates a walker and processes repos' do
        command.run
        expect(GitTreeWalker).to have_received(:new).with(args, options: an_instance_of(Hash))
        expect(mock_walker).to have_received(:find_and_process_repos)
      end
    end
  end
end
