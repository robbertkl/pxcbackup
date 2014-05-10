require 'shellwords'

require 'pxcbackup/backup'

module PXCBackup
  class Repo
    attr_reader :path

    def initialize(path, options = {})
      @path = path
      @which = PathResolver.new(options)
    end

    def backups
      backups = []
      Dir.foreach(@path) do |file|
        path = File.join(@path, file)
        next unless File.file?(path)
        next unless Backup.regexp.match(path)
        backups << Backup.new(self, path)
      end
      backups.sort
    end

    def delete(backup)
      verify(backup)
      File.delete(backup.path)
    end

    def stream_command(backup)
      verify(backup)
      "#{@which.cat.shellescape} #{backup.path.shellescape}"
    end

    private

    def verify(backup)
      raise 'backup does not belong to this repo' if backup.repo != self
    end
  end
end

