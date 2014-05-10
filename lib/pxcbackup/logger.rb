module PXCBackup
  module Logger
    @verbosity_level = 0
    @indentation = 0
    @color_output = false
    @partial = false

    def self.raise_verbosity
      @verbosity_level += 1
    end

    def self.increase_indentation
      @indentation += 1
    end

    def self.decrease_indentation
      @indentation -= 1
    end

    def self.color_output=(value)
      @color_output = value
    end

    def self.output(message, skip_newline = false)
      if @partial
        puts
        increase_indentation
        @partial = false
      end
      print '  ' * @indentation + message
      puts unless skip_newline
      $stdout.flush
    end

    def self.action_start(message)
      return unless @verbosity_level >= 1
      output "#{message}: ", true
      @partial = true
    end

    def self.action_end(message)
      return unless @verbosity_level >= 1
      if @partial
        puts message
        @partial = false
      else
        output message
        decrease_indentation
      end
    end

    def self.info(message)
      output message if @verbosity_level >= 1
    end

    def self.debug(message)
      output blue(message) if @verbosity_level >= 2
    end

    def self.action(message)
      return yield unless @verbosity_level >= 1

      action_start(message)
      t1 = Time.now
      begin
        result = yield
      rescue => e
        action_end(red('fail'))
        raise e
      end
      t2 = Time.now
      action_end(green('done') + ' (%.1fs)' % (t2 - t1))
      result
    end

    def self.colorize(text, color_code)
      @color_output ? "\e[#{color_code}m#{text}\e[0m" : text
    end

    def self.red(text)
      colorize(text, 31);
    end

    def self.green(text)
      colorize(text, 32)
    end

    def self.yellow(text)
      colorize(text, 33);
    end

    def self.blue(text)
      colorize(text, 34);
    end
  end
end
