module PXCBackup
  class Backup
    attr_reader :repo, :path

    def initialize(repo, path)
      @repo = repo
      @path = path
      raise 'invalid backup name' unless match
    end

    def self.regexp
      /\/(\d+)_(full|incr)\.(xbstream|tar)(\.xbcrypt)?$/
    end

    def ==(other)
      @path == other.path && @repo == other.repo
    end

    def <=>(other)
      compare = time <=> other.time
      compare = remote? ? -1 : 1 if compare == 0 && remote? != other.remote?
      compare
    end

    def to_s
      time.to_s
    end

    def time
      Time.at(match[:timestamp].to_i)
    end

    def type
      type = match[:type]
      type = 'incremental' if type == 'incr'
      type.to_sym
    end

    def stream
      match[:stream].to_sym
    end

    def encrypted?
      match[:encrypted]
    end

    def full?
      type == :full
    end

    def incremental?
      type == :incremental
    end

    def remote?
      @repo.is_a? RemoteRepo
    end

    def delete
      @repo.delete(self)
    end

    def stream_command
      @repo.stream_command(self)
    end

    private

    def match
      match = self.class.regexp.match(@path)
      return nil unless match
      {
        :timestamp => match[1],
        :type => match[2],
        :stream => match[3],
        :encrypted => !!match[4],
      }
    end
  end
end
