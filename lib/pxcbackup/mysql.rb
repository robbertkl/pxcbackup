require 'shellwords'

module PXCBackup
  class MySQL
    attr_reader :datadir

    def initialize(options = {})
      @which = PathResolver.new(options)
      @username = options[:mysql_user] || 'root'
      @password = options[:mysql_pass] || ''
      @datadir = options[:mysql_datadir] || get_variable('datadir') || '/var/lib/mysql'
      raise 'Could not find mysql data dir' unless File.directory?(@datadir)
    end

    def auth
      "--user=#{@username.shellescape} --password=#{@password.shellescape}"
    end

    def exec(query)
      lines = `echo #{query.shellescape} | #{@which.mysql.shellescape} #{auth} 2> /dev/null`.lines.to_a
      return nil if lines.empty?

      keys = lines.shift.chomp.split("\t")
      rows = []
      lines.each do |line|
        values = line.chomp.split("\t")
        row = {}
        keys.each_with_index do |val, key|
          row[val] = values[key]
        end
        rows << row
      end
      rows
    end

    def get_variable(variable, scope = 'GLOBAL')
      result = exec("SHOW #{scope} VARIABLES LIKE '#{variable}'")
      result ? result.first['Value'] : nil
    end

    def set_variable(variable, value, scope = 'GLOBAL')
      exec("SET #{scope} #{variable}=#{value}")
    end

    def get_status(variable)
      result = exec("SHOW STATUS LIKE '#{variable}'")
      result ? result.first['Value'] : nil
    end
  end
end
