require 'optparse'
require 'time'
require 'yaml'

require 'pxcbackup/backupper'
require 'pxcbackup/version'

module PXCBackup
  class Application
    def initialize(argv)
      parse_options(argv)

      config = File.join(ENV['HOME'], '.pxcbackup')
      if @options[:config]
        config = @options[:config]
        raise 'cannot find given config file' unless File.file?(config)
      end
      if File.file?(config)
        config_options = YAML.load_file(config)
        config_options = config_options.inject({}) { |hash, (k, v)| hash[k.to_sym] = v; hash }
        @options = config_options.merge(@options)
      end
    end

    def run
      backupper = Backupper.new(@options)

      case @command
      when 'create'
        backupper.make_backup(@options)
      when 'list'
        backupper.list_backups
      when 'restore'
        time = @arguments.any? ? Time.parse(@arguments.first) : Time.now
        backupper.restore_backup(time, !!@options[:skip_confirmation])
      end
    end

    def parse_options(argv)
      @options ||= {}
      parser = OptionParser.new do |opt|
        opt.banner = "Usage: #{$0} COMMAND [OPTIONS]"
        opt.separator ''
        opt.separator 'Commands'
        opt.separator '     create             create a new backup'
        opt.separator '     help               show this help'
        opt.separator '     list               list available backups'
        opt.separator '     restore [time]     restore to a point in time'
        opt.separator ''
        opt.separator 'Options'

        opt.on('-c', '--config', '=CONFIG_FILE', 'config file to use instead of ~/.pxcbackup') do |config_file|
          @options[:config] = config_file
        end

        opt.on('-d', '--dir', '=BACKUP_DIR', 'local repository to store backups') do |backup_dir|
          @options[:backup_dir] = backup_dir
        end

        opt.on('-f', '--full', 'create a full backup') do
          @options[:type] = :full
        end

        opt.on('-i', '--incremental', 'create an incremental backup') do
          @options[:type] = :incremental
        end

        opt.on('-l', '--local', 'stay local, i.e. do not communicate with S3') do
          @options[:local] = true
        end

        opt.on('-r', '--remote', '=REMOTE_URI', 'remote URI to sync backups to, e.g. s3://my-aws-bucket/') do |remote|
          @options[:remote] = remote
        end

        opt.on('-v', '--verbose', 'verbose output') do
          @options[:verbose] = true
        end

        opt.on('--version', 'print version and exit') do
          puts "pxcbackup #{VERSION}"
          exit
        end

        opt.on('-y', '--yes', 'skip confirmation on backup restore') do
          @options[:skip_confirmation] = true
        end
      end

      begin
        @command, *@arguments = parser.parse(argv)
        if @command == 'help'
          puts parser
          exit
        end
        raise 'no command given' if @command.to_s == ''
        raise "invalid command #{@command}" unless ['create', 'list', 'restore'].include?(@command)
      rescue => e
        abort "#{$0}: #{e.message}\n#{parser}"
      end
    end
  end
end
