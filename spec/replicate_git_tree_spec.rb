require_relative '../lib/replicate_git_tree'

RSpec.describe('Replicate Git Tree') do
  it 'finds git repos under a directory' do
    dirs = directories_to_process '..'
    expect(dirs.length).to be(1)
  end
end
