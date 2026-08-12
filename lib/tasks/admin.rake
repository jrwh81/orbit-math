namespace :admin do
  desc "Grant admin access to a user by username: bin/rails admin:promote[username]"
  task :promote, [:username] => :environment do |_t, args|
    username = args[:username]
    abort "Usage: bin/rails admin:promote[username]" if username.blank?

    user = User.find_by(username: username.downcase)
    abort "No user found with username '#{username}'" unless user

    user.update!(admin: true)
    puts "#{user.username} is now an admin."
  end

  desc "Revoke admin access from a user by username: bin/rails admin:demote[username]"
  task :demote, [:username] => :environment do |_t, args|
    username = args[:username]
    abort "Usage: bin/rails admin:demote[username]" if username.blank?

    user = User.find_by(username: username.downcase)
    abort "No user found with username '#{username}'" unless user

    user.update!(admin: false)
    puts "#{user.username} is no longer an admin."
  end

  desc "List all current admins"
  task list: :environment do
    admins = User.where(admin: true)
    if admins.any?
      admins.each { |u| puts "#{u.username} (#{u.email.presence || "no email"})" }
    else
      puts "No admins yet. Run bin/rails admin:promote[username] to create one."
    end
  end
end
