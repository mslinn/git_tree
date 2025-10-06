require_relative 'spec_helper'

RSpec.describe(GemSupport) do
  it 'finds common prefix for one string with many slashes' do
    strings = [
      '/root/sub3/sub1'
    ]
    actual = described_class.common_prefix strings
    expect(actual).to eq '/root/sub3'
  end

  it 'finds common prefix for one string with 1 slash' do
    strings = [
      '/root'
    ]
    actual = described_class.common_prefix strings
    expect(actual).to eq ''

    actual = described_class.common_prefix(strings, allow_root_match: true)
    expect(actual).to eq '/'
  end

  it 'finds common prefix for two strings' do
    strings = [
      '/root/sub1/sub2/blah',
      '/root/sub3/sub1'
    ]
    actual = described_class.common_prefix strings
    expect(actual).to eq '/root'
  end

  it 'finds common prefix for multiple strings' do
    strings = [
      '/root/sub1/sub2/blah',
      '/root/sub1/sub2',
      '/root/sub1',
      '/root/sub3/sub1'
    ]
    actual = described_class.common_prefix strings
    expect(actual).to eq '/root'
  end

  it 'finds common prefix with 2 roots' do
    strings = [
      '/root/sub1/sub2/blah',
      '/root/sub1/sub2',
      '/root/sub1',
      '/root2/sub3/sub1'
    ]
    actual = described_class.common_prefix strings
    expect(actual).to eq ''

    actual = described_class.common_prefix(strings, allow_root_match: true)
    expect(actual).to eq '/'
  end
end
