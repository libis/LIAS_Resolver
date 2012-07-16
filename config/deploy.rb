require "rvm/capistrano"
require 'capistrano-deploytags'
set :rvm_type, :system

default_run_options[:pty] = true

set :application, "LIAS Resolver"
set :repository,  "git@github.com:Kris-LIBIS/LIAS_Resolver.git"

set :scm, :git
set :branch, 'master'
set :stage, 'production'

set :deploy_to, "/opt/libis/LIAS_Resolver"
set :user, "exlibris"
set :use_sudo, false

set :keep_releases, 2

server "resolver.lias.be", :app, :web, :db, :primary => true

# if you want to clean up old releases on each deploy uncomment this:

namespace :remote do

  task :fw_off do
    run "sudo /etc/init.d/firewall stop"
  end

  task :fw_on do
    run "sudo /etc/init.d/firewall start"
  end
  
  task :create_dirs do
    run "mkdir -p #{shared_path}/log"
    run "mkdir -p #{shared_path}/pid"
  end

  task :create_symlinks do
    run "ln -ns #{shared_path}/log #{current_path}/"
    run "ln -ns #{shared_path}/pid #{current_path}/"
    run "ln -ns #{shared_path}/lias_resolver.yml #{current_path}/"
  end

  task :stop_server do
    run "sudo /etc/init.d/thin stop"
  end

  task :start_server do
    run "sudo /etc/init.d/thin start"
  end

end

after  "deploy:setup" , "remote:create_dirs"

before "deploy:update_code", "remote:fw_off"
after  "deploy:update_code", "remote:fw_on"

before "deploy:update", "remote:stop_server"
after  "deploy:update", "remote:create_symlinks", "remote:start_server", "deploy:cleanup"

