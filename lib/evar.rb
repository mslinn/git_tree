class Evar
  attr_accessor :children, :name, :short_value, :full_value, :parent

  def initialize(name, value, parent = nil)
    @name = name
    @children = []
    @full_value = value
    @parent = parent
  end

  def add_child(child)
    @children << child
    self
  end

  def node_count
    @full_value.count '/'
  end

  def to_s
    "export @name=" + @short_value ? @short_value : @full_value
  end
end

class Evars
  attr_accessor :root

  def initialize(root)
    @root = root
    @evars = [] # all evars
    @nodes = [] # array of lists of nodes
  end

  def add(evar)
    @evars << evar
  end

  # Return the longest path prefix that is a prefix of all paths in array.
  # If array is empty, return the empty string ('').
  def self.common_prefix(paths, allow_root_match: false)
    return '' if paths.empty?

    return paths.first.split('/').slice(0...-1).join('/') if paths.length <= 1

    arr = paths.sort
    first = arr.first.split('/')
    last = arr.last.split('/')
    i = 0
    i += 1 while first[i] == last[i] && i <= first.length
    result = first.slice(0, i).join('/')

    result.empty? && allow_root_match ? '/' : result
  end

  # TODO: make this more useful
  # Generates output (export statements)
  def list
    puts @evars.join("\n") + "\n"
  end

  # Group evars by their number of nodes.
  # Store groups into an array of lists of evars.
  def organize_nodes
    @nodes = []
    @evars.each { |evar| @nodes[evar.node_count] << evar }
  end

  def common_prefix(evars)

  end
end
