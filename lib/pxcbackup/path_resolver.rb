require 'shellwords'

module PXCBackup
  class PathResolver
    def initialize(options = {})
      @options = options
      @paths = {}
    end

    def method_missing(name, *arguments)
      unless @paths[name]
        @paths[name] = @options["#{name.to_s}_path".to_sym] || `which #{name.to_s.shellescape}`.strip
        raise "cannot find path for #{name.to_s}" unless File.file?(@paths[name])
      end
      @paths[name]
    end
  end
end
