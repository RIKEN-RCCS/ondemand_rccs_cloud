require 'open3'
require 'timeout'
require 'yaml'

# Summarizes how free each Slurm partition is, for the dashboard's partition card.
# Partitions are grouped by hardware as listed in partition_groups.yml (next to lib/),
# and partitions sharing nodes (e.g. ai-h100l and ai-h100l-pu) are folded into one entry.
module PartitionStatus
  COMMAND_TIMEOUT = 5 # seconds
  GROUPS_FILE = File.expand_path('../partition_groups.yml', __dir__)
  OTHER_GROUP = 'Other'

  # States in which a node can take new jobs now or once its current jobs end;
  # anything else (drain, down, maint, resv, ...) is counted as down.
  IN_SERVICE_STATES = %w[idle mix alloc comp plnd].freeze

  class Error < StandardError; end

  Group = Struct.new(:name, :entries, keyword_init: true)

  # unit is "GPU" for partitions whose nodes have GPU gres (GPUs are allocated one by one there),
  # otherwise "node". total/free count only in-service nodes; down counts the rest.
  Entry = Struct.new(:name, :members, :unit, :free, :total, :down, :pending_by_member, keyword_init: true) do
    def pending
      pending_by_member.values.sum
    end

    def level
      return :down if total.zero?
      return :full if free.zero?
      free < total ? :partial : :free
    end

    # "ai-h100l / -pu" for merged partitions, plain name otherwise
    def label
      ([name] + (members - [name]).map { |m| m.delete_prefix(name) }).join(' / ')
    end
  end

  def self.fetch
    config = YAML.safe_load(File.read(GROUPS_FILE)) || {}
    merge = config['merge'] || {}
    canonical = ->(partition) { merge.fetch(partition, partition) }

    entries = build_entries(sinfo_nodes, pending_jobs, canonical)
    group_entries(entries, config['groups'] || [])
  rescue SystemCallError, Psych::Exception => e
    raise Error, e.message
  end

  # One row per (partition, node): [partition, node, state, gpus, gpus_used]
  def self.sinfo_nodes
    stdout = run('sinfo', '-h', '-N', '-O', 'PartitionName:60,NodeHost:60,StateCompact:20,Gres:100,GresUsed:100')
    stdout.each_line.map(&:split).select { |f| f.size == 5 }.map do |partition, node, state, gres, gres_used|
      [partition, node, state.downcase.delete('^a-z'), gpu_count(gres), gpu_count(gres_used)]
    end
  end
  private_class_method :sinfo_nodes

  # Pending job count per partition; a job queued on "a,b" counts for both
  def self.pending_jobs
    run('squeue', '-h', '-t', 'PD', '-o', '%P').split.flat_map { |p| p.split(',') }.tally
  end
  private_class_method :pending_jobs

  def self.build_entries(rows, pending, canonical)
    rows.group_by { |row| canonical.call(row[0]) }.map do |name, partition_rows|
      members = partition_rows.map(&:first).uniq.sort_by { |m| [m == name ? 0 : 1, m] }
      # Merged partitions list the same nodes twice; count each node once
      nodes = partition_rows.uniq { |row| row[1] }
      in_service = nodes.select { |row| IN_SERVICE_STATES.include?(row[2]) }
      gpu = nodes.any? { |row| row[3].positive? }

      total, free = if gpu
                      [in_service.sum { |r| r[3] }, in_service.sum { |r| %w[idle mix].include?(r[2]) ? r[3] - r[4] : 0 }]
                    else
                      [in_service.size, in_service.count { |r| r[2] == 'idle' }]
                    end

      Entry.new(name: name, members: members, unit: gpu ? 'GPU' : 'node',
                free: [free, 0].max, total: total, down: nodes.size - in_service.size,
                pending_by_member: members.to_h { |m| [m, pending.fetch(m, 0)] })
    end
  end
  private_class_method :build_entries

  def self.group_entries(entries, groups)
    by_name = entries.to_h { |e| [e.name, e] }
    result = groups.map do |group|
      Group.new(name: group['name'], entries: Array(group['partitions']).filter_map { |p| by_name.delete(p) })
    end
    result << Group.new(name: OTHER_GROUP, entries: by_name.values.sort_by(&:name)) unless by_name.empty?
    result.reject { |g| g.entries.empty? }
  end
  private_class_method :group_entries

  # Sum of GPU counts in a gres string such as "gpu:B300-275GB:7(IDX:0-6)" or "gpu:2,gpu:a100:1"
  def self.gpu_count(gres)
    gres.scan(/gpu(?::[^:,(]+)?:(\d+)/).sum { |(n)| n.to_i }
  end
  private_class_method :gpu_count

  def self.run(*cmd)
    stdout, status = Timeout.timeout(COMMAND_TIMEOUT) { Open3.capture2(*cmd) }
    raise Error, "#{cmd.first} exited with #{status.exitstatus}" unless status.success?

    stdout
  rescue Timeout::Error
    raise Error, "command timed out: #{cmd.join(' ')}"
  rescue Errno::ENOENT => e
    raise Error, e.message
  end
  private_class_method :run
end
