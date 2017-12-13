require 'shellwords'

require 'pxcbackup/backup'
require 'pxcbackup/command'
require 'pxcbackup/repo'

module PXCBackup
  class RemoteRepo < Repo
    def initialize(path, options = {})
      super(path, options)
      @which.s3cmd
    end

    def backups
      backups = []
      output = Command.run("#{@which.s3cmd.shellescape} ls #{@path.shellescape}")
      output[:stdout].lines.to_a.each do |line|
        path = line.chomp.split[3]
        next unless Backup.regexp.match(path)
        backups << Backup.new(self, path)
      end
      backups.sort
    end

    def sync(local_repo)
      source = File.join(local_repo.path, '/')
      target = File.join(path, '/')
      Command.run("#{@which.s3cmd.shellescape} sync --no-progress --delete-removed #{source.shellescape} #{target.shellescape}")
    end

    def delete(backup)
      verify(backup)
      Command.run("#{@which.s3cmd.shellescape} del #{backup.path.shellescape}")
    end

    def stream_command(backup)
      verify(backup)
      "#{@which.s3cmd.shellescape} get --no-progress #{backup.path.shellescape} -"
    end
  end
end
