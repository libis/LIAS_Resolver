require "rvm/capistrano"
require 'capistrano-deploytags'
set :rvm_type, :system

default_run_options[:pty] = true

set :application, "LIAS Resolver"
set :repository,  "git@github.com:Kris-LIBIS/LIAS_Resolver.git"

set :scm, :git

set :deploy_to, "/opt/libis/LIAS_Resolver"
set :user, "exlibris"
set :use_sudo, false

server "resolver.lias.be", :app, :web, :db, :primary => true

# if you want to clean up old releases on each deploy uncomment this:

namespace :remote do

  task :fw_off do
    run "sudo /etc/init.d/firewall stop"
  end

  task :fw_on do
    run "sudo /etc/init.d/firewall start"
  end

  task :create_symlinks do
    run "mkdir -fp #{shared_path}/log"
    run "ln -s #{shared_path}/log #{current_path}/log"
    run "mkdir -fp #{shared_path}/pid"
    run "ln -s #{shared_path}/log #{current_path}/pid"
  end

  task :stop_server do
    run "sudo /etc/thin stop"
  end

  task :start_server do
    run "sudo /etc/thin start"
  end

end


after  "deploy:update", "deploy:cleanup"

before "deploy:update_code", "remote:fw_off"
after  "deploy:update_code", "remote:fw_on"

before "deploy:update", "remote:stop_server"
after  "deploy:update", "remote:start_server"

