require 'tmpdir'
require_relative '../spec_helper'
require_relative '../../lib/commands/git_update'
require_relative '../../lib/util/log'
require_relative '../../lib/util/git_tree_walker_private'

describe GitTree::UpdateCommand do
  include Logging

  subject(:command) { described_class.new(args, options: options) }

  let(:args) { ['/fake/root'] }
  let(:mock_walker) { instance_double(GitTreeWalker, abbreviate_path: '~/repo1', process: nil, config: instance_double(GitTree::GTConfig, git_timeout: 30)) }
  let(:mock_runner) { instance_double(CommandRunner) }
  let(:repo_dir) { '/fake/root/repo1' }
  let(:options) { { walker: mock_walker, runner: mock_runner } }

  before do
    allow(Logging).to receive(:log)
    allow(Logging).to receive(:verbosity).and_return(Logging::NORMAL)
  end

  describe '#run' do
    it 'initializes the GitTreeWalker after parsing options' do
      # This test ensures that the walker is created with the final, parsed arguments,
      # not the initial ones, which was a source of a previous bug.
      command = described_class.new(['-v', '/some/dir'], options: { runner: mock_runner })
      allow(GitTreeWalker).to receive(:new).and_return(mock_walker)

      command.run

      # It should be called with the arguments left *after* option parsing.
      expect(GitTreeWalker).to have_received(:new).with(['/some/dir'], options: {})
    end

    context 'when git pull is successful' do
      let(:pull_output) { 'Already up to date.' }

      it 'logs the update message' do
        allow(mock_walker).to receive(:process).and_yield(repo_dir, 0, mock_walker)
        allow(mock_runner).to receive(:run).with('git pull', repo_dir)
                                           .and_return([pull_output, instance_double(Process::Status, exitstatus: 0)])

        command.run

        expect(Logging).to have_received(:log).with(Logging::NORMAL, 'Updating ~/repo1', :green)
      end

      it 'logs verbose output when verbosity is high' do
        allow(mock_walker).to receive(:process).and_yield(repo_dir, 0, mock_walker)
        allow(Logging).to receive(:verbosity).and_return(Logging::VERBOSE)
        allow(mock_runner).to receive(:run).with('git pull', repo_dir)
                                           .and_return([pull_output, instance_double(Process::Status, exitstatus: 0)])

        command.run

        expect(Logging).to have_received(:log).with(Logging::NORMAL, pull_output.strip, :green)
      end
    end

    context 'when git pull fails' do
      let(:error_output) { 'fatal: not a git repository' }

      it 'logs an error message' do
        allow(mock_walker).to receive(:process).and_yield(repo_dir, 0, mock_walker)
        allow(mock_runner).to receive(:run).with('git pull', repo_dir)
                                           .and_return([error_output, instance_double(Process::Status, exitstatus: 128)])

        command.run

        expect(Logging).to have_received(:log).with(Logging::NORMAL, '[ERROR] git pull failed in ~/repo1 (exit code 128):', :red)
        expect(Logging).to have_received(:log).with(Logging::NORMAL, error_output.strip, :red)
      end
    end

    context 'when git pull times out' do
      it 'logs a timeout error' do
        allow(mock_walker).to receive(:process).and_yield(repo_dir, 0, mock_walker)
        allow(mock_runner).to receive(:run).with('git pull', repo_dir).and_raise(Timeout::Error)

        command.run

        expect(Logging).to have_received(:log).with(
          Logging::NORMAL,
          '[TIMEOUT] Thread 0: git pull timed out in ~/repo1',
          :red
        )
      end
    end

    context 'when no git repositories are found' do
      it 'does not call the runner' do
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
        # A real walker will be created by the command itself.
        test_options = { runner: mock_runner, serial: true }
        command = described_class.new(args, options: test_options)
        allow(mock_runner).to receive(:run)
          .with('git pull', repo_path).and_return(['', instance_double(Process::Status, exitstatus: 0)])

        command.run
        expect(mock_runner).to have_received(:run).with('git pull', repo_path).once
      end

      it 'passes the correct walker instance to process_repo' do
        # This test guards against a regression where the wrong object (a block parameter
        # instead of the main instance variable) was passed, causing a NoMethodError.
        test_options = { runner: mock_runner, serial: true }
        command = described_class.new(args, options: test_options)

        # We spy on the private method `process_repo` to check its arguments.
        allow(command).to receive(:process_repo).and_call_original
        allow(mock_runner).to receive(:run)
          .with('git pull', repo_path).and_return(['', instance_double(Process::Status, exitstatus: 0)])

        command.run

        expect(command).to have_received(:process_repo).with(an_instance_of(GitTreeWalker), repo_path, 0)
      end
    end
  end
end
