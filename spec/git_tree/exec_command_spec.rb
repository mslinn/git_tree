require 'spec_helper'
require_relative '../../lib/commands/git_exec'
require_relative '../../lib/util/log'

describe GitTree::ExecCommand do
  include Logging

  subject(:command) { described_class.new(args) }

  let(:mock_walker) { instance_double(GitTreeWalker) }
  let(:mock_runner) { instance_double(CommandRunner) }
  let(:command_to_run) { 'ls -l' }
  let(:repo_dir) { '/fake/root/repo1' }

  before do
    # Inject test doubles before each test
    command.walker = mock_walker
    command.runner = mock_runner

    # Stub methods on the command object itself to act as spies
    allow(command).to receive(:exit)
    allow(command).to receive(:help)
    allow(Logging).to receive(:log)
    allow(Logging).to receive(:log_stdout)
  end

  describe '#run' do
    context 'with insufficient arguments' do
      let(:args) { [command_to_run] } # Only one argument

      it 'calls help and exits' do
        command.run
        expect(command).to have_received(:help).with('At least one root and a command must be specified.')
      end
    end

    context 'when the shell command is successful' do
      let(:args) { ['/fake/root', command_to_run] }
      let(:command_output) { "file1.txt\nfile2.txt" }

      it 'executes the command and logs output to stdout' do
        allow(mock_walker).to receive(:process).and_yield(repo_dir, 0, nil)
        allow(mock_runner).to receive(:run).with(command_to_run, repo_dir)
                                           .and_return([command_output, instance_double(Process::Status, success?: true)])

        command.run
        expect(Logging).to have_received(:log_stdout).with(command_output.strip)
        expect(Logging).not_to have_received(:log) # Verify it doesn't log to stderr
      end
    end

    context 'when the shell command fails' do
      let(:args) { ['/fake/root', command_to_run] }
      let(:error_output) { 'ls: not found' }

      it 'executes the command and logs output to stderr' do
        allow(mock_walker).to receive(:process).and_yield(repo_dir, 0, nil)
        allow(mock_runner).to receive(:run).with(command_to_run, repo_dir)
                                           .and_return([error_output, instance_double(Process::Status, success?: false)])

        command.run
        expect(Logging).to have_received(:log).with(Logging::QUIET, error_output.strip, :red)
        expect(Logging).not_to have_received(:log_stdout)
      end
    end

    context 'when the runner raises an exception' do
      let(:args) { ['/fake/root', command_to_run] }
      let(:error_message) { 'A critical error occurred' }

      it 'rescues the exception and logs an error message to stderr' do
        allow(mock_walker).to receive(:process).and_yield(repo_dir, 0, nil)
        allow(mock_runner).to receive(:run).with(command_to_run, repo_dir).and_raise(StandardError, error_message)

        expected_log_message = "Error: '#{error_message}' from executing '#{command_to_run}' in #{repo_dir}"
        command.run
        expect(Logging).to have_received(:log).with(Logging::QUIET, expected_log_message, :red)
        expect(Logging).not_to have_received(:log_stdout)
      end
    end
  end
end
