require_relative '../spec_helper'
require_relative '../../lib/commands/git_evars'
require_relative '../../lib/util/log'

describe GitTree::EvarsCommand do
  subject(:command) { described_class.new(args) }

  include Logging

  let(:mock_walker) { instance_double(GitTreeWalker, root_map: {}, display_roots: []) }
  let(:mock_optimizer) { instance_double(ZoweeOptimizer, optimize: []) }

  before do
    allow(GitTreeWalker).to receive(:new).and_return(mock_walker)
    allow(mock_walker).to receive(:find_and_process_repos)
    allow(ZoweeOptimizer).to receive(:new).and_return(mock_optimizer)
    allow(command).to receive(:log_stdout)
  end

  describe '#run' do
    context 'with no arguments' do
      let(:args) { [] }

      it 'creates a walker and processes repos' do
        command.run
        expect(GitTreeWalker).to have_received(:new).with([], options: an_instance_of(Hash))
        expect(mock_walker).to have_received(:find_and_process_repos)
      end
    end

    context 'with --zowee option' do
      let(:args) { ['--zowee', '$work'] }

      it 'uses the ZoweeOptimizer' do
        command.run
        expect(ZoweeOptimizer).to have_received(:new).with(mock_walker.root_map)
        expect(mock_optimizer).to have_received(:optimize)
      end
    end
  end
end
