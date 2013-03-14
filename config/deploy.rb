require 'rvm/capistrano'
require 'capistrano-deploytags'
require 'bundler/capistrano'

set :rvm_type, :local
set :rvm_ruby_string, 'ruby@resolver'

default_run_options[:pty] = true

set :application, 'LIAS Resolver'
set :repository, 'git@github.com:Kris-LIBIS/LIAS_Resolver.git'

set :scm, :git
set :branch, 'master'
set :stage, 'production'

set :deploy_to, '/opt/libis/LIAS_Resolver'
set :user, 'lias'
set :use_sudo, false

set :keep_releases, 2

server 'libis-p-rosetta-3', :app, :web, :db, primary: true

namespace :remote do

  task :fw_off do
    run 'sudo /etc/init.d/firewall stop'
  end

  task :fw_on do
    run 'sudo /etc/init.d/firewall start'
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
    run 'sudo /etc/init.d/lias_resolver stop'
  end

  task :start_server do
    run 'sudo /etc/init.d/lias_resolver start'
  end

end

after  'deploy:setup', 'remote:create_dirs'

before 'deploy:update_code', 'remote:fw_off'
after  'deploy:update_code', 'remote:fw_on'

before 'deploy:update', 'remote:stop_server'
after  'deploy:update', 'remote:create_symlinks', 'remote:start_server', 'deploy:cleanup'

