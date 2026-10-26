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
