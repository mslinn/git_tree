require_relative '../spec_helper'

RSpec.describe(GemSupport) do
  it 'trims to level' do
    paths = [
      '/root/sub3/sub1'
    ]
    actual = described_class.trim_to_level(paths, 1)
    expect(actual).to eq ['/root']

    actual = described_class.trim_to_level(paths, 2)
    expect(actual).to eq ['/root/sub3']

    actual = described_class.trim_to_level(paths, 3)
    expect(actual).to eq ['/root/sub3/sub1']

    actual = described_class.trim_to_level(paths, 4)
    expect(actual).to eq ['/root/sub3/sub1']
  end

  it 'finds level 1 root for one path with many slashes' do
    paths = [
      '/root/sub3/sub1'
    ]
    actual = described_class.roots(paths, 1)
    expect(actual).to eq '/root/sub3'
  end

  it 'finds level 1 root for one path with 1 slash' do
    paths = [
      '/root'
    ]
    actual = described_class.roots(paths, 1)
    expect(actual).to eq ''

    actual = described_class.roots(paths, 1, allow_root_match: true)
    expect(actual).to eq '/'
  end

  it 'finds roots for two paths' do
    paths = [
      '/root/sub1/sub2/blah',
      '/root/sub3/sub1'
    ]
    actual = described_class.roots(paths, 1)
    expect(actual).to eq '/root'
  end

  it 'finds level 1 root for multiple paths' do
    paths = [
      '/root/sub1/sub2/blah',
      '/root/sub1/sub2',
      '/root/sub1',
      '/root/sub3/sub1'
    ]
    actual = described_class.roots(paths, 1)
    expect(actual).to eq '/root'
  end
end
