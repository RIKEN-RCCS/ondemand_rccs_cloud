require 'etc'
require 'open3'
require 'timeout'

# Reads the caller's Lustre user quota on /hs/work0, where /home/users lives.
# Home directories have no project quota on R-CCS Cloud, so the user quota is
# the limit that applies; it counts everything the user owns on WORK0, not
# only the home directory. There is no file-count limit, so only space is read.
module HomeQuota
  MOUNT_POINT = '/hs/work0'
  COMMAND_TIMEOUT = 5 # seconds

  class Error < StandardError; end

  Result = Struct.new(:used_kb, :limit_kb, keyword_init: true) do
    def percent
      return nil if limit_kb.to_i.zero?
      (used_kb.to_f / limit_kb * 100).round(1)
    end

    def used_bytes
      used_kb.to_i * 1024
    end

    def limit_bytes
      limit_kb.to_i * 1024
    end
  end

  def self.fetch(user = Etc.getpwuid(Process.uid).name)
    stdout, status = run('lfs', 'quota', '-q', '-u', user, '--blocks', '--block-hardlimit', MOUNT_POINT)
    raise Error, "lfs quota exited with #{status.exitstatus}" unless status.success?

    # lfs marks a value with "*" once it exceeds the limit
    used_kb, limit_kb = stdout.split.map { |v| Integer(v.delete('*')) rescue nil }
    raise Error, "unexpected lfs quota output: #{stdout.inspect}" if used_kb.nil? || limit_kb.nil?

    Result.new(used_kb: used_kb, limit_kb: limit_kb)
  end

  def self.run(*cmd)
    Timeout.timeout(COMMAND_TIMEOUT) { Open3.capture2(*cmd) }
  rescue Timeout::Error
    raise Error, "command timed out: #{cmd.join(' ')}"
  rescue Errno::ENOENT => e
    raise Error, e.message
  end
  private_class_method :run
end
