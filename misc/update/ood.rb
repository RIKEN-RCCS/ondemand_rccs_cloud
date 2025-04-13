# coding: utf-8
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

Rails.application.config.after_initialize do
  OodFilesApp.candidate_favorite_paths.tap do |paths|
    `groups`.split.each do |group|
      user_path = File.join("/lvs0", group, ENV['USER'])
      group_path = File.join("/lvs0", group)

      if File.readable?(user_path) && File.executable?(user_path)
        paths << FavoritePath.new(user_path)
      elsif File.readable?(group_path) && File.executable?(group_path)
        paths << FavoritePath.new(group_path)
      end
    end
  end
end

def script(name, queue, hours, gpus = "")
  yaml =  "  job_name: #{name}\n"
  yaml << "    queue_name: #{queue}\n"
  yaml << "    native:\n"

  case queue
  when "qc-a100"
    gpus_option = gpus.to_s.strip.empty? ? "--gpus=1" : "--gpus=#{gpus}"
    yaml << "      - \"#{gpus_option}\ -t #{hours}:00:00\"\n"
  when "ai-h100l-pu"
    yaml << "      - \"-t 0:30:00\"\n"
  when "ai-h200-brc"
    yaml << "      - \"--gpus=1 -t 8:00:00\"\n"
  else
    yaml << "      - \"-t #{hours}:00:00\"\n"
  end

  yaml
end
