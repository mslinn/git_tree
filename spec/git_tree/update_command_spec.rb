require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/commands/git_update'
require_relative '../../lib/util/log'
require_relative '../../lib/util/git_tree_walker_private'

describe GitTree::UpdateCommand do
  subject(:command) { described_class.new(args, options: options) }

  let(:command) { described_class.new(args) }

  include Logging

  let(:args) { ['/fake/root'] }
  let(:mock_walker) { instance_double(GitTreeWalker, abbreviate_path: '~/repo1', process: nil) }
  let(:mock_runner) { instance_double(CommandRunner) }
  let(:repo_dir) { '/fake/root/repo1' }
  let(:options) { { walker: mock_walker, runner: mock_runner } }

  before do
    command.walker = mock_walker
    command.runner = mock_runner

    allow(command).to receive(:log)
    allow(Logging).to receive(:verbosity).and_return(Logging::NORMAL)
  end

  describe '#run' do
    context 'when git pull is successful' do
      let(:pull_output) { 'Already up to date.' }

      it 'logs the update message' do
        allow(mock_walker).to receive(:process).and_yield(nil, repo_dir, 0, mock_walker)
        allow(mock_runner).to receive(:run).with('git pull', repo_dir)
                                           .and_return([pull_output, instance_double(Process::Status, exitstatus: 0)])

        command.run

        expect(command).to have_received(:log).with(Logging::NORMAL, 'Updating ~/repo1', :green)
      end

      it 'logs verbose output when verbosity is high' do
        allow(mock_walker).to receive(:process).and_yield(nil, repo_dir, 0, mock_walker)
        allow(Logging).to receive(:verbosity).and_return(Logging::VERBOSE)
        allow(mock_runner).to receive(:run).with('git pull', repo_dir)
                                           .and_return([pull_output, instance_double(Process::Status, exitstatus: 0)])

        command.run

        expect(command).to have_received(:log).with(Logging::NORMAL, pull_output.strip, :green)
      end
    end

    context 'when git pull fails' do
      let(:error_output) { 'fatal: not a git repository' }

      it 'logs an error message' do
        allow(mock_walker).to receive(:process).and_yield(nil, repo_dir, 0, mock_walker)
        allow(mock_runner).to receive(:run).with('git pull', repo_dir)
                                           .and_return([error_output, instance_double(Process::Status, exitstatus: 128)])

        command.run

        expect(command).to have_received(:log).with(Logging::NORMAL, '[ERROR] git pull failed in ~/repo1 (exit code 128):', :red)
        expect(command).to have_received(:log).with(Logging::NORMAL, error_output.strip, :red)
      end
    end

    context 'when git pull times out' do
      it 'logs a timeout error' do
        allow(mock_walker).to receive(:process).and_yield(nil, repo_dir, 0, mock_walker)
        allow(mock_runner).to receive(:run).with('git pull', repo_dir).and_raise(Timeout::Error)

        command.run

        expect(command).to have_received(:log).with(
          Logging::NORMAL,
          '[TIMEOUT] Thread 0: git pull timed out in ~/repo1',
          :red
        )
      end
    end

    context 'when no git repositories are found' do
      it 'does not call the runner' do
        # Configure the walker to find no repos
        allow(mock_walker).to receive(:process) # This will not yield
        allow(mock_runner).to receive(:run)
        allow(mock_runner).to receive(:run) # Make it a spy

        command.run

        expect(mock_runner).not_to have_received(:run)
      end
    end

    context 'with a real GitTreeWalker and file system' do
      let(:tmpdir) { Dir.mktmpdir }
      let(:repo_path) { File.join(tmpdir, 'real_repo') }
      let(:args) { [tmpdir] }

      before do
        # Create a fake git repo
        Dir.mkdir(repo_path)
        system('git', 'init', repo_path, out: File::NULL, err: File::NULL)
      end

      after do
        FileUtils.remove_entry(tmpdir)
      end

      it 'finds the repository and calls the runner' do
        # Instantiate the command with the path to the temp dir and inject the mock runner.
        # The '--serial' flag ensures synchronous execution for the test.
        options = { runner: mock_runner }
        command = described_class.new(args + ['--serial'], options: options)
        # A real walker will be created by the command itself.
        test_options = { runner: mock_runner, serial: true }
        command = described_class.new(args, options: test_options)
        allow(mock_runner).to receive(:run)
          .with('git pull', repo_path).and_return(['', instance_double(Process::Status, exitstatus: 0)])

        command.run
        expect(mock_runner).to have_received(:run).with('git pull', repo_path).once
      end
    end
  end
end
