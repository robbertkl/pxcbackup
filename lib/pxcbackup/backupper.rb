require 'fileutils'
require 'tmpdir'

require 'pxcbackup/array'
require 'pxcbackup/backup'
require 'pxcbackup/command'
require 'pxcbackup/logger'
require 'pxcbackup/mysql'
require 'pxcbackup/path_resolver'
require 'pxcbackup/remote_repo'
require 'pxcbackup/repo'

module PXCBackup
  class Backupper
    def initialize(options)
      @threads = options[:threads] || 1
      @memory = options[:memory] || '100M'

      @defaults_file = options[:defaults_file] || nil
      @throttle = options[:throttle] || nil
      @encrypt = options[:encrypt] || nil
      @encrypt_key = options[:encrypt_key] || nil

      @which = PathResolver.new(options)

      local_repo_path = options[:backup_dir]
      @local_repo = local_repo_path ? Repo.new(local_repo_path, options) : nil

      remote_repo_path = options[:remote]
      @remote_repo = remote_repo_path && !options[:local] ? RemoteRepo.new(remote_repo_path, options) : nil

      @mysql = MySQL.new(options)
    end

    def make_backup(options = {})
      type = options[:type] || :full
      stream = options[:stream] || :xbstream
      compress = options[:compress] || false
      compact = options[:compact] || false
      desync_wait = options[:desync_wait] || 60
      retention = options[:retention] || 100

      raise 'cannot find backup dir' unless @local_repo && File.directory?(@local_repo.path)
      raise 'cannot enable encryption without encryption key' if @encrypt && !@encrypt_key

      arguments = [
        @mysql.auth,
        '--no-timestamp',
        "--extra-lsndir=#{@local_repo.path}",
        "--stream=#{stream.to_s}",
        '--galera-info',
      ]

      if compress
        arguments << '--compress'
      end

      if compact
        arguments << '--compact'
      end

      if @encrypt
        arguments << "--encrypt=#{@encrypt.shellescape}"
        arguments << "--encrypt-key=#{@encrypt_key.shellescape}"
      end

      filename = "#{Time.now.to_i}"
      if type == :incremental
        last_info = read_backup_info(File.join(@local_repo.path, 'xtrabackup_checkpoints'))
        arguments << '--incremental'
        arguments << "--incremental-lsn=#{last_info[:to_lsn]}"
        filename << "_incr"
      else
        filename << '_full'
      end
      filename << ".#{stream.to_s}"
      filename << '.xbcrypt' if @encrypt

      desync_enable(desync_wait)

      Dir.mktmpdir('pxcbackup-') do |dir|
        arguments << dir.shellescape
        Logger.action "Creating backup #{filename}" do
          innobackupex(arguments, File.join(@local_repo.path, filename))
        end
      end

      desync_disable
      rotate(retention)

      if @remote_repo
        Logger.action 'Syncing backups to remote repository' do
          @remote_repo.sync(@local_repo)
        end
      end
    end

    def restore_backup(time, options = {})
      skip_confirmation = options[:skip_confirmation] || false
      mysql_start_command = options[:mysql_start_command] || "#{@which.service.shellescape} mysql start"
      mysql_stop_command = options[:mysql_stop_command] || "#{@which.service.shellescape} mysql stop"

      incremental_backups = []
      all_backups.reverse_each do |backup|
        incremental_backups.unshift(backup) if backup.time <= time
        break if incremental_backups.any? && backup.full?
      end
      raise "cannot find any backup before #{time}" if incremental_backups.empty?
      raise "cannot find a full backup before #{time}" unless incremental_backups.first.full?
      restore_time = incremental_backups.last.time

      full_backup = incremental_backups.shift

      Logger.info "[1/#{incremental_backups.size + 1}] Processing #{full_backup.type.to_s} backup from #{full_backup.time}"
      Logger.increase_indentation
      with_extracted_backup(full_backup) do |full_backup_path, full_backup_info|
        raise 'unexpected backup type' unless full_backup_info[:backup_type] == full_backup.type
        raise 'unexpected start LSN' unless full_backup_info[:from_lsn] == 0

        compact = full_backup_info[:compact]

        if full_backup_info[:compress]
          Logger.action 'Decompressing' do
            innobackupex(['--decompress', full_backup_path.shellescape])
          end
        end

        if incremental_backups.any?
          Logger.action "Preparing base backup (LSN #{full_backup_info[:to_lsn]})" do
            innobackupex(['--apply-log', '--redo-only', full_backup_path.shellescape])
          end

          current_lsn = full_backup_info[:to_lsn]

          index = 2
          incremental_backups.each do |incremental_backup|
            Logger.decrease_indentation
            Logger.info "[#{index}/#{incremental_backups.size + 1}] Processing #{incremental_backup.type.to_s} backup from #{incremental_backup.time}"
            Logger.increase_indentation
            with_extracted_backup(incremental_backup) do |incremental_backup_path, incremental_backup_info|
              raise 'unexpected backup type' unless incremental_backup_info[:backup_type] == incremental_backup.type
              raise 'unexpected start LSN' unless incremental_backup_info[:from_lsn] == current_lsn

              compact ||= incremental_backup_info[:compact]

              if incremental_backup_info[:compress]
                Logger.action 'Decompressing' do
                  innobackupex(['--decompress', incremental_backup_path.shellescape])
                end
              end

              Logger.action "Applying increment (LSN #{incremental_backup_info[:from_lsn]} -> #{incremental_backup_info[:to_lsn]})" do
                innobackupex(['--apply-log', '--redo-only', full_backup_path.shellescape, "--incremental-dir=#{incremental_backup_path.shellescape}"])
              end

              current_lsn = incremental_backup_info[:to_lsn]
            end
            index += 1
          end
        end

        Logger.decrease_indentation

        action = 'Final prepare'
        arguments = [
          '--apply-log',
        ]

        if compact
          action << ' + rebuild indexes'
          arguments << '--rebuild-indexes'
        end

        Logger.action "#{action}" do
          arguments << full_backup_path.shellescape
          innobackupex(arguments)
        end

        Logger.action 'Attempting to restore Galera info' do
          restore_galera_info(full_backup_path)
        end

        mysql_datadir = @mysql.datadir.chomp('/')
        mysql_datadir_old = mysql_datadir + '_YYYYMMDDhhmmss'

        unless skip_confirmation
          puts
          puts '    BACKUP IS NOW READY TO BE RESTORED'
          puts "    BACKUP TIMESTAMP: #{restore_time}"
          puts '    PLEASE CONFIRM THIS ACTION'
          puts
          puts '    This will:'
          puts '    - stop the MySQL server'
          puts "    - move the current datadir to #{mysql_datadir_old}"
          puts "    - restore the backup to #{mysql_datadir}"
          puts '    - start the MySQL server'
          puts
          puts '    Afterwards you will have to:'
          puts '    - confirm everything is working and synced correctly'
          puts '    - manually create a new full backup (to re-allow incremental backups)'
          puts
          puts '    If MySQL server cannot be started, this might be because this is the'
          puts '    only (remaining) Galera node. If so, manually bootstrap the cluster:'
          puts '    # service mysql bootstrap-pxc'
          puts
          print '    Please type "yes" to continue: '
          confirmation = STDIN.gets.chomp
          puts
          raise 'did not confirm restore' unless confirmation == 'yes'
        end

        Logger.action 'Stopping MySQL server' do
          Command.run(mysql_stop_command)
        end

        stat = File.stat(mysql_datadir)
        uid = stat.uid
        gid = stat.gid

        mysql_datadir_old = mysql_datadir + '_' + Time.now.strftime('%Y%m%d%H%M%S')
        Logger.action "Moving current datadir to #{mysql_datadir_old}" do
          File.rename(mysql_datadir, mysql_datadir_old)
        end

        Logger.action "Restoring backup to #{mysql_datadir}" do
          Dir.mkdir(mysql_datadir)
          innobackupex(['--move-back', full_backup_path.shellescape])
        end

        Logger.action "Chowning #{mysql_datadir}" do
          FileUtils.chown_R(uid, gid, mysql_datadir)
        end

        if @local_repo
          xtrabackup_checkpoints_file = File.join(@local_repo.path, 'xtrabackup_checkpoints')
          if File.file?(xtrabackup_checkpoints_file)
            Logger.action "Removing last backup info" do
              File.delete(xtrabackup_checkpoints_file)
            end
          end
        end

        Logger.action 'Starting MySQL server' do
          Command.run(mysql_start_command)
        end
      end
    end

    def list_backups
      all_backups.each { |backup| puts backup }
    end

    private

    def all_backups
      backups = []
      backups += @local_repo.backups if @local_repo
      backups += @remote_repo.backups if @remote_repo
      backups = backups.uniq_by { |backup| backup.time }
      backups.sort
    end

    def desync_enable(wait = 60)
      Logger.info 'Setting wsrep_desync=ON'
      @mysql.set_variable('wsrep_desync', 'ON')
      Logger.action "Waiting for #{wait} seconds" do
        sleep(wait)
      end
    end

    def desync_disable
      Logger.action 'Waiting until wsrep_local_recv_queue is empty' do
        sleep(2) until @mysql.get_status('wsrep_local_recv_queue') == '0'
      end
      Logger.info 'Setting wsrep_desync=OFF'
      @mysql.set_variable('wsrep_desync', 'OFF')
    end

    def rotate(retention)
      Logger.action 'Checking if we have old backups to remove' do
        @local_repo.backups.each do |backup|
          days = (Time.now - backup.time) / 86400
          break if days < retention && backup.full?
          Logger.info "Deleting backup from #{backup.time}"
          backup.delete
        end
      end
    end

    def innobackupex(arguments, output_file = nil)
      command = @which.innobackupex.shellescape
      # --defaults-file has to be the first option passed!
      command << " --defaults-file=#{@defaults_file.shellescape}" if @defaults_file

      arguments += [
        "--ibbackup=#{@which.xtrabackup.shellescape}",
        "--parallel=#{@threads}",
        "--compress-threads=#{@threads}",
        "--rebuild-threads #{@threads}",
        "--use-memory=#{@memory}",
        "--tmpdir=#{Dir.tmpdir.shellescape}",
      ]
      arguments << "--throttle=#{@throttle.shellescape}" if @throttle

      command << ' ' + arguments.join(' ')
      command << " > #{output_file.shellescape}" if output_file
      result = Command.run(command)
      raise 'unexpected output from innobackupex' unless result[:stderr].lines.to_a.last.match(/: completed OK!$/)
    end

    def read_backup_info(file)
      raise "cannot open #{file}" unless File.file?(file)
      result = {}
      File.open(file, 'r') do |file|
        file.each_line do |line|
          key, value = line.chomp.split(/\s*=\s*/, 2)
          case key
          when 'backup_type'
            value = 'full' if value == 'full-backuped'
            value = value.to_sym
          when /_lsn$/
            value = value.to_i
          when 'compact'
            value = (value == '1')
          end
          result[key.to_sym] = value
        end
      end
      result
    end

    def with_extracted_backup(backup)
      Dir.mktmpdir('pxcbackup-') do |dir|
        command = backup.stream_command
        action = 'Extracting'
        if backup.encrypted?
          raise 'need encryption algorithm and key to decrypt this backup' unless @encrypt && @encrypt_key
          command << " | #{@which.xbcrypt.shellescape} -d --encrypt-algo=#{@encrypt.shellescape} --encrypt-key=#{@encrypt_key.shellescape}"
          action << ' + decrypting'
        end
        command <<
          case backup.stream
          when :xbstream
            " | #{@which.xbstream.shellescape} -x -C #{dir.shellescape}"
          when :tar
            " | #{@which.tar.shellescape} -ixf - -C #{dir.shellescape}"
          end
        Logger.action action do
          Command.run(command)
        end

        checkpoints_file = File.join(dir, 'xtrabackup_checkpoints')
        unless File.file?(checkpoints_file)
          Logger.warning 'Could not find xtrabackup_checkpoints: trying to skip faulty backup'
          return
        end

        xtrabackup_binary_file = File.join(dir, 'xtrabackup_binary')
        File.delete(xtrabackup_binary_file) if File.file?(xtrabackup_binary_file)

        info = read_backup_info(checkpoints_file)
        info[:compress] = Dir.glob(File.join(dir, '**', '*.qp')).any?

        yield(dir, info)
      end
    end

    def restore_galera_info(dir)
      galera_info_file = File.join(dir, 'xtrabackup_galera_info')
      return unless File.file?(galera_info_file)
      uuid, seqno = nil
      File.open(galera_info_file, 'r') do |file|
        uuid, seqno = file.gets.chomp.split(':')
      end

      version = @mysql.get_status('wsrep_provider_version')
      if version
        version = version.split('(').first
      else
        current_grastate_file = File.join(@mysql.datadir, 'grastate.dat')
        if File.file?(current_grastate_file)
          File.open(current_grastate_file, 'r') do |file|
            file.each_line do |line|
              match = line.match(/^version:\s+(.*)$/)
              if match
                version = match[1]
                break
              end
            end
          end
        end
      end
      return unless version

      File.open(File.join(dir, 'grastate.dat'), 'w') do |file|
        file.write("# GALERA saved state\n")
        file.write("version: #{version}\n")
        file.write("uuid:    #{uuid}\n")
        file.write("seqno:   #{seqno}\n")
        file.write("cert_index:\n")
      end
    end
  end
end
