require 'spec_helper'
require_relative '../../lib/commands/git_update'
require_relative '../../lib/util/log'

describe GitTree::UpdateCommand do
  subject(:command) { described_class.new(args) }

  include Logging

  let(:args) { ['/fake/root'] }
  let(:mock_walker) { instance_double(GitTreeWalker, abbreviate_path: '~/repo1') }
  let(:mock_runner) { instance_double(CommandRunner) }
  let(:repo_dir) { '/fake/root/repo1' }

  before do
    command.walker = mock_walker
    command.runner = mock_runner

    allow(mock_walker).to receive(:process).and_yield(nil, repo_dir, 0, mock_walker)
    allow(command).to receive(:log)
    allow(Logging).to receive(:verbosity).and_return(Logging::NORMAL)
  end

  describe '#run' do
    context 'when git pull is successful' do
      let(:pull_output) { 'Already up to date.' }

      it 'logs the update message' do
        allow(mock_runner).to receive(:run).with('git pull', repo_dir)
                                           .and_return([pull_output, double(exitstatus: 0)])

        command.run

        expect(command).to have_received(:log).with(Logging::NORMAL, 'Updating ~/repo1', :green)
      end

      it 'logs verbose output when verbosity is high' do
        allow(Logging).to receive(:verbosity).and_return(Logging::VERBOSE)
        allow(mock_runner).to receive(:run).with('git pull', repo_dir)
                                           .and_return([pull_output, double(exitstatus: 0)])

        command.run

        expect(command).to have_received(:log).with(Logging::NORMAL, pull_output.strip, :green)
      end
    end

    context 'when git pull fails' do
      let(:error_output) { 'fatal: not a git repository' }

      it 'logs an error message' do
        allow(mock_runner).to receive(:run).with('git pull', repo_dir)
                                           .and_return([error_output, double(exitstatus: 128)])

        command.run

        expect(command).to have_received(:log).with(Logging::NORMAL, '[ERROR] git pull failed in ~/repo1 (exit code 128):', :red)
        expect(command).to have_received(:log).with(Logging::NORMAL, error_output.strip, :red)
      end
    end

    context 'when git pull times out' do
      it 'logs a timeout error' do
        allow(mock_runner).to receive(:run).with('git pull', repo_dir).and_raise(Timeout::Error)

        command.run

        expect(command).to have_received(:log).with(
          Logging::NORMAL,
          '[TIMEOUT] Thread 0: git pull timed out in ~/repo1',
          :red
        )
      end
    end
  end
end
