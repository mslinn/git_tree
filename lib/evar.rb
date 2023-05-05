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

  def initialize(root, allow_root_match: false)
    @allow_root_match = allow_root_match
    @root = root
    @evars = [] # all evars
    @nodes = [] # array of lists of nodes
  end

  def add(evar)
    @evars << evar
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
end
