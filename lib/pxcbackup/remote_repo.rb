require 'shellwords'

require	'pxcbackup/backup'
require	'pxcbackup/repo'

module PXCBackup
  class RemoteRepo < Repo
    def initialize(path, options = {})
      super(path, options)
      @which.s3cmd
    end

    def backups
      backups = []
      `#{@which.s3cmd.shellescape} ls #{@path.shellescape}`.lines.to_a.each do |line|
        path = line.chomp.split[3]
        next unless Backup.regexp.match(path)
        backups << Backup.new(self, path)
      end
      backups.sort
    end

    def sync(local_repo)
      source = File.join(local_repo.path, '/')
      target = File.join(path, '/')
      system("#{@which.s3cmd.shellescape} sync --no-progress --delete-removed #{source.shellescape} #{target.shellescape} > /dev/null")
    end

    def delete(backup)
      verify(backup)
      system("#{@which.s3cmd.shellescape} del #{backup.path.shellescape} > /dev/null")
    end

    def stream_command(backup)
      verify(backup)
      "#{@which.s3cmd.shellescape} get #{backup.path.shellescape} -"
    end
  end
end
