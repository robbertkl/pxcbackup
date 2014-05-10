require 'open3'

require 'pxcbackup/logger'

module PXCBackup
  module Command
    def self.run(command, ignore_exit_status = false)
      Logger.debug "# #{command}"
      captured_stdout = ''
      captured_stderr = ''
      Open3.popen3(command) do |stdin, stdout, stderr|
        stdin.close
        until stdout.closed? && stderr.closed?
          sockets = []
          sockets << stdout unless stdout.closed?
          sockets << stderr unless stderr.closed?
          IO.select(sockets).flatten.compact.each do |socket|
            begin
              data = socket.readpartial(1024)
              captured_stdout << data if socket == stdout
              captured_stderr << data if socket == stderr
            rescue EOFError
              socket.close
            end
          end
        end
      end
      raise 'command "#{command.split.first}" exited with a non-zero status' unless $?.success? || ignore_exception
      { :stdout => captured_stdout, :stderr => captured_stderr, :exit_status => $?.exitstatus }
    end
  end
end
