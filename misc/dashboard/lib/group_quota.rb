require 'etc'
require 'open3'
require 'timeout'

# Reads the Lustre project quota of the caller's group directories on /lvs0.
# Each /lvs0/<group> is a symlink into dne0/dne1 and carries a project quota
# (space and file count); the group quota itself has no limit there.
# Users may belong to several groups, so every group with a directory is returned.
module GroupQuota
  MOUNT_POINT = '/lvs0'
  COMMAND_TIMEOUT = 5 # seconds

  class Error < StandardError; end

  Result = Struct.new(:used_kb, :limit_kb, :used_files, :limit_files, keyword_init: true) do
    def percent
      return nil if limit_kb.to_i.zero?
      (used_kb.to_f / limit_kb * 100).round(1)
    end

    def files_percent
      return nil if limit_files.to_i.zero?
      (used_files.to_f / limit_files * 100).round(1)
    end

    def used_bytes
      used_kb.to_i * 1024
    end

    def limit_bytes
      limit_kb.to_i * 1024
    end
  end

  def self.group_dir(group_name)
    "#{MOUNT_POINT}/#{group_name}"
  end

  # The caller's groups that have a directory under /lvs0, sorted for a stable display order.
  def self.group_names
    Process.groups.map { |gid| safe_group_name(gid) }.compact
           .select { |g| File.directory?(group_dir(g)) }.uniq.sort
  end

  def self.fetch(group_name)
    project_id = project_id_for(File.realpath(group_dir(group_name)))
    stdout, status = run('lfs', 'quota', '-q', '-p', project_id,
                         '--blocks', '--block-hardlimit', '--inodes', '--inode-hardlimit',
                         MOUNT_POINT)
    raise Error, "lfs quota exited with #{status.exitstatus}" unless status.success?

    # lfs marks a value with "*" once it exceeds the limit
    values = stdout.split.map { |v| Integer(v.delete('*')) rescue nil }
    raise Error, "unexpected lfs quota output: #{stdout.inspect}" if values.size != 4 || values.any?(&:nil?)

    used_kb, limit_kb, used_files, limit_files = values
    Result.new(used_kb: used_kb, limit_kb: limit_kb, used_files: used_files, limit_files: limit_files)
  rescue SystemCallError => e
    raise Error, e.message
  end

  def self.project_id_for(dir)
    stdout, status = run('lfs', 'project', '-d', dir)
    raise Error, "lfs project exited with #{status.exitstatus}" unless status.success?

    project_id = stdout.split.first
    raise Error, "could not determine project id for #{dir}" if project_id.nil?

    project_id
  end
  private_class_method :project_id_for

  def self.safe_group_name(gid)
    Etc.getgrgid(gid).name
  rescue ArgumentError
    nil
  end
  private_class_method :safe_group_name

  def self.run(*cmd)
    Timeout.timeout(COMMAND_TIMEOUT) { Open3.capture2(*cmd) }
  rescue Timeout::Error
    raise Error, "command timed out: #{cmd.join(' ')}"
  rescue Errno::ENOENT => e
    raise Error, e.message
  end
  private_class_method :run
end
