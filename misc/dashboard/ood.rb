#NavConfig.categories=["Interactive Apps", "Lecture Apps", "Passenger Apps"]
#NavConfig.categories=["Files", "Interactive Apps", "Passenger Apps"]
#NavConfig.categories_whitelist=true

#OodFilesApp.candidate_favorite_paths.tap do |paths|
#  DIR=`id -Gn`.split(" ")
#  DIR.each{|d|
#    dir="/lvs0/" + d
#    if Dir.exist?(dir) then
#      paths.concat Pathname.glob(dir)
#    end
#  }
#end
#

def custom_queue()
  <<~YAML
  custom_queue:
      widget: select
      label: Partition
      options:
        - [ "fx700",       data-hide-gpus: true ]
        - [ "a100",        data-hide-gpus: true ]
        - [ "mi100",       data-hide-gpus: true ]
        - [ "r340",        data-hide-gpus: true ]
        - [ "genoa",       data-hide-gpus: true ]
        - [ "genoa-m",     data-hide-gpus: true ]
        - [ "qc-a100"                           ]
        - [ "qc-h100",     data-hide-gpus: true ]
        - [ "qc-gh200",    data-hide-gpus: true ]
        - [ "qc-mi210",    data-hide-gpus: true ]
        - [ "qc-mi250",    data-hide-gpus: true ]
        - [ "qc-pvc",      data-hide-gpus: true ]
        - [ "ai-h100l",    data-hide-gpus: true ]
        - [ "ai-h100l-pu", data-hide-gpus: true, data-hide-bc-num-hours: true ]
        - [ "ai-h200-brc", data-hide-gpus: true, data-hide-bc-num-hours: true ]
      help: When selecting ai-h100l-pu or ai-h200-brc, the maximum run time will be 30 minutes and 8 hours respectively.
YAML
end

def custom_queue_only_x86()
  <<~YAML
  custom_queue:
      widget: select
      label: Partition
      options:
        - [ "a100",        data-hide-gpus: true ]
        - [ "mi100",       data-hide-gpus: true ]
        - [ "r340",        data-hide-gpus: true ]
        - [ "genoa",       data-hide-gpus: true ]
        - [ "genoa-m",     data-hide-gpus: true ]
        - [ "qc-a100"                           ]
        - [ "qc-h100",     data-hide-gpus: true ]
        - [ "qc-mi210",    data-hide-gpus: true ]
        - [ "qc-mi250",    data-hide-gpus: true ]
        - [ "qc-pvc",      data-hide-gpus: true ]
        - [ "ai-h100l",    data-hide-gpus: true ]
        - [ "ai-h100l-pu", data-hide-gpus: true, data-hide-bc-num-hours: true ]
        - [ "ai-h200-brc", data-hide-gpus: true, data-hide-bc-num-hours: true ]
      help: When selecting ai-h100l-pu or ai-h200-brc, the maximum run time will be 30 minutes and 8 hours respectively.
YAML
end                                                                                                     

def bc_num_hours()
  <<~YAML
  bc_num_hours:
      widget: "number_field"
      label: "Maximum run time (1 - 24 hours)"
      required: true
      min: 1
      max: 24
      step: 1
YAML
end

def gpus()
  <<~YAML
  gpus:
      widget: "number_field"
      label: "Number of GPUs (1 - 8)"
      required: true
      value: 1
      min: 1
      max: 8
      step: 1
YAML
end

def script(name, queue, gpus = "")
  yaml =  "  job_name: #{name}\n"
  yaml << "    queue_name: #{queue}\n"

  case queue
  when "qc-a100"
    yaml << "    native:\n"
    gpus_option = gpus.to_s.strip.empty? ? "--gpus=1" : "--gpus=#{gpus}"
    yaml << "      - \"#{gpus_option}\"\n"
  when "ai-h100l-pu"
    yaml << "    native:\n"
    yaml << "      - \"-t 0:30:00\"\n"
  when "ai-h200-brc"
    yaml << "    native:\n"
    yaml << "      - \"--gpus=1 -t 8:00:00\"\n"
  end

  yaml
end
