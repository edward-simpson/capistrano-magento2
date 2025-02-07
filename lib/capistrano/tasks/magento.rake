##
 # Copyright © 2016 by David Alger. All rights reserved
 # 
 # Licensed under the Open Software License 3.0 (OSL-3.0)
 # See included LICENSE file for full text of OSL-3.0
 # 
 # http://davidalger.com/contact/
 ##

include Capistrano::Magento2::Helpers
include Capistrano::Magento2::Setup

namespace :magento do

  namespace :app do
    namespace :config do
      desc 'Create dump of application config'
      task :dump do
        on primary fetch(:magento_deploy_setup_role) do
          within release_path do
            execute :magento, 'app:config:dump'
          end
        end
      end
      
      desc 'Import data from shared config files'
      task :import do
        on primary fetch(:magento_deploy_setup_role) do
          within release_path do
            execute :magento, 'app:config:import --no-interaction'
          end
        end
      end
      
      desc 'Checks if config propagation requires update'
      task :status do
        on primary fetch(:magento_deploy_setup_role) do
          within release_path do
            execute :magento, 'app:config:status'
          end
        end
      end
    end
  end

  namespace :cache do
    desc 'Flush Magento cache storage'
    task :flush do
      on cache_hosts do
        within release_path do
          execute :magento, 'cache:flush'
        end
      end
    end
    
    desc 'Clean Magento cache by types'
    task :clean do
      on cache_hosts do
        within release_path do
          execute :magento, 'cache:clean'
        end
      end
    end
    
    desc 'Enable Magento cache'
    task :enable do
      on cache_hosts do
        within release_path do
          execute :magento, 'cache:enable'
        end
      end
    end
    
    desc 'Disable Magento cache'
    task :disable do
      on cache_hosts do
        within release_path do
          execute :magento, 'cache:disable'
        end
      end
    end
    
    desc 'Check Magento cache enabled status'
    task :status do
      on cache_hosts do
        within release_path do
          execute :magento, 'cache:status'
        end
      end
    end
  
    namespace :varnish do
      # TODO: Document what the magento:cache:varnish:ban task is for and how to use it. See also magento/magento2#4106
      desc 'Add ban to Varnish for url(s)'
      task :ban do
        on primary fetch(:magento_deploy_setup_role) do
          # TODO: Document use of :ban_pools and :varnish_cache_hosts in project config file
          next unless any? :ban_pools
          next unless any? :varnish_cache_hosts
          
          within release_path do
            for pool in fetch(:ban_pools) do
              for cache_host in fetch(:varnish_cache_hosts) do
                execute :curl, %W{-s -H 'X-Pool: #{pool}' -X PURGE #{cache_host}}
              end
            end
          end
        end
      end
    end
  end
  
  namespace :composer do
    desc 'Run composer install'
    task :install => :auth_config do

      on release_roles :all do
        within release_path do
          composer_flags = '--prefer-dist --no-interaction'

          if fetch(:magento_deploy_no_dev)
            composer_flags += ' --no-dev'
          end

          if fetch(:magento_deploy_production)
            composer_flags += ' --optimize-autoloader'
          end

          execute :composer, "install #{composer_flags} 2>&1"

          if test "[ -f #{release_path}/update/composer.json ]"   # can't count on this, but emit warning if not present
            execute :composer, "install #{composer_flags} -d ./update 2>&1"
          else
            puts "\e[0;31m    Warning: ./update/composer.json does not exist in repository!\n\e[0m\n"
          end
        end
      end
    end

    desc 'Run composer dump-autoload'
    task 'dump-autoload' do

      on release_roles :all do
        within release_path do
          composer_flags = '--no-interaction'

          if fetch(:magento_deploy_no_dev)
            composer_flags += ' --no-dev'
          end

          if fetch(:magento_deploy_production)
            composer_flags += ' --optimize'
          end

           if fetch(:composer_authoritative_classmap)
              composer_flags += ' --classmap-authoritative'
            end

          execute :composer, "dump-autoload #{composer_flags} 2>&1"
        end
      end
    end

    task :auth_config do
      on release_roles :all do
        within release_path do
          if fetch(:magento_auth_public_key) and fetch(:magento_auth_private_key)
            execute :composer, :config, '-q',
              fetch(:magento_auth_repo_name),
              fetch(:magento_auth_public_key),
              fetch(:magento_auth_private_key),
              verbosity: Logger::DEBUG
          end
        end
      end
    end
  end

  namespace :deploy do
    namespace :mode do
      desc "Enables production mode"
      task :production do
        on release_roles(:all), in: :sequence, wait: 1 do
          within release_path do
            execute :magento, "deploy:mode:set production --skip-compilation"
          end
        end
      end
      
      desc "Displays current application mode"
      task :show do
        on release_roles :all do
          within release_path do
            execute :magento, "deploy:mode:show"
          end
        end
      end
    end

    task :check do
      on release_roles :all do
        next unless any? :linked_files_touch
        on release_roles :all do |host|
          join_paths(shared_path, fetch(:linked_files_touch)).each do |file|
            unless test "[ -f #{file} ]"
              execute :touch, file
            end
          end
        end
      end
    end

    task :verify do
      is_err = false
      on release_roles :all do
        unless test "[ -f #{release_path}/app/etc/config.php ]"
          error "\e[0;31mThe repository is missing app/etc/config.php. Please install the application and retry!\e[0m"
          exit 1  # only need to check the repo once, so we immediately exit
        end

        # Checking app/etc/env.php in shared_path vs release_path to support the zero-side-effect
        # builds as implemented in the :detect_scd_config hook of deploy.rake
        unless test %Q[#{SSHKit.config.command_map[:php]} -r '
              $cfg = include "#{shared_path}/app/etc/env.php";
              exit((int)!isset($cfg["install"]["date"]));
          ']
          error "\e[0;31mError on #{host}:\e[0m No environment configuration could be found." +
                " Please configure app/etc/env.php and retry!"
          is_err = true
        end
      end
      exit 1 if is_err
    end
  end

  namespace :setup do
    desc 'Updates the module load sequence and upgrades database schemas and data fixtures'
    task :upgrade do
      on primary fetch(:magento_deploy_setup_role) do
        within release_path do
          warn "\e[0;31mWarning: Use of magento:setup:upgrade on production systems is discouraged." +
               " See https://github.com/davidalger/capistrano-magento2/issues/34 for details.\e[0m\n"

          execute :magento, 'setup:upgrade --keep-generated'
        end
      end
    end
    
    namespace :db do
      desc 'Checks if DB schema or data requires upgrade'
      task :status do
        on primary fetch(:magento_deploy_setup_role) do
          within release_path do
            execute :magento, 'setup:db:status'
          end
        end
      end
      
      task :upgrade do
        on primary fetch(:magento_deploy_setup_role) do
          within release_path do
            db_status = capture :magento, 'setup:db:status --no-ansi', verbosity: Logger::INFO
            
            if not db_status.to_s.include? 'All modules are up to date'
              execute :magento, 'setup:db-schema:upgrade'
              execute :magento, 'setup:db-data:upgrade'
            end
          end
        end
      end
      
      desc 'Upgrades data fixtures'
      task 'schema:upgrade' do
        on primary fetch(:magento_deploy_setup_role) do
          within release_path do
            execute :magento, 'setup:db-schema:upgrade'
          end
        end
      end
      
      desc 'Upgrades database schema'
      task 'data:upgrade' do
        on primary fetch(:magento_deploy_setup_role) do
          within release_path do
            execute :magento, 'setup:db-data:upgrade'
          end
        end
      end
    end
    
    desc 'Sets proper permissions on application'
    task :permissions do
      on release_roles :all do
        within release_path do
          execute :find, release_path, "-type d ! -perm #{fetch(:magento_deploy_chmod_d).to_i} -exec chmod #{fetch(:magento_deploy_chmod_d).to_i} {} +"
          execute :find, release_path, "-type f ! -perm #{fetch(:magento_deploy_chmod_f).to_i} -exec chmod #{fetch(:magento_deploy_chmod_f).to_i} {} +"
          
          fetch(:magento_deploy_chmod_x).each() do |file|
            execute :chmod, "+x #{release_path}/#{file}"
          end
        end
      end
    end
    
    desc 'Sets proper selinux context on directories which are written to by web processes'
    task :selinux do
      on release_roles :all do
        with path: '/usr/sbin:$PATH' do
          if test "selinuxenabled"
            within release_path do
              fetch(:magento_deploy_chcon_dirs).each() do |dir|
                execute :chcon, "-RP -t #{fetch(:magento_deploy_chcon_type)} #{release_path}/#{dir}"
              end
            end
          end
        end
      end
    end

    namespace :di do
      desc 'Runs dependency injection compilation routine'
      task :compile do
        on release_roles :all do
          within release_path do
            with mage_mode: :production do
              execute :magento, "setup:di:compile"
            end
          end
        end
      end
    end
    
    namespace 'static-content' do
      desc 'Deploys static view files'
      task :deploy do
        on release_roles :all do
          with mage_mode: :production do
            deploy_languages = fetch(:magento_deploy_languages)
            if deploy_languages.count() > 0
              deploy_languages = deploy_languages.join(' ').prepend(' ')
            else
              deploy_languages = nil
            end

            deploy_themes = fetch(:magento_deploy_themes)
            if deploy_themes.count() > 0
              deploy_themes = deploy_themes.join(' -t ').prepend(' -t ')
            else
              deploy_themes = nil
            end

            deploy_jobs = fetch(:magento_deploy_jobs)
            if deploy_jobs
              deploy_jobs = " --jobs #{deploy_jobs}"
            else
              deploy_jobs = nil
            end

            # Static content compilation strategies that can be one of the following:
            # quick (default), standard (like previous versions) or compact
            compilation_strategy = fetch(:magento_deploy_strategy)
            if compilation_strategy
              compilation_strategy =  " -s #{compilation_strategy}"
            end

            within release_path do
              execute :magento, "setup:static-content:deploy#{compilation_strategy}#{deploy_jobs}#{deploy_languages}#{deploy_themes}"
            end

            # Set the deployed_version of static content to ensure it matches across all hosts
            upload!(StringIO.new(deployed_version), "#{release_path}/pub/static/deployed_version.txt")
          end
        end
      end
    end
  end

  namespace :maintenance do
    desc 'Enable maintenance mode'
    task :enable do
      on release_roles :all do
        within release_path do
          execute :magento, 'maintenance:enable'
        end
      end
    end

    # Internal command used to check if maintenance mode is neeeded and disable when zero-down deploy is
    # possible or when maintenance mode was previously enabled on the deploy target
    task :check do
      on primary fetch(:magento_deploy_setup_role) do
        maintenance_enabled = nil
        disable_maintenance = false     # Do not disable maintenance mode in absence of positive release checks

        if test "[ -d #{current_path} ]"
          within current_path do
            # If maintenance mode is already enabled, enable maintenance mode on new release and disable management to
            # avoid disabling maintenance mode in the event it was manually enabled prior to deployment
            info "Checking maintenance status..."
            maintenance_status = capture :magento, 'maintenance:status', raise_on_non_zero_exit: false

            if maintenance_status.to_s.include? 'maintenance mode is active'
              info "Maintenance mode is currently active."
              maintenance_enabled = true
            else
              info "Maintenance mode is currently inactive."
              maintenance_enabled = false
            end
            info ""
          end
        end

        # If maintenance is currently active, enable it on the newly deployed release
        if maintenance_enabled
          info "Enabling maintenance mode on new release to match active status of current release."
          on release_roles :all do
            within release_path do
              execute :magento, 'maintenance:enable'
            end
          end
          info ""
        end

        within release_path do
          info "Checking database status..."
          # Check setup:db:status output and if out-of-date do not disable maintenance mode
          database_status = capture :magento, 'setup:db:status', raise_on_non_zero_exit: false
          database_uptodate = false

          if database_status.to_s.include? 'All modules are up to date'
            info "All modules are up to date."
            info ""
            database_uptodate = true
          else
            puts "      #{database_status.gsub("\n", "\n      ").sub(" Run 'setup:upgrade' to update your DB schema and data.", "")}"
          end

          # Check app:config:status output and if out-of-date do not disable maintenance mode
          info "Checking config status..."
          config_status = capture :magento, 'app:config:status', raise_on_non_zero_exit: false
          config_uptodate = false

          if config_status.to_s.include? 'Config files are up to date'
            info "Config files are up to date."
            config_uptodate = true
          else
            puts "      #{config_status.gsub("\n", "\n      ").sub(" Run app:config:import or setup:upgrade command to synchronize configuration.", "")}"
          end
          info ""

          # If both checks above reported up-to-date status checks disable maintenance mode
          if database_uptodate and config_uptodate
            disable_maintenance = true
          end

          if maintenance_enabled
            info "Disabling maintenance mode management..."
            info "Maintenance mode was already active prior to deploy."
            set :magento_deploy_maintenance, false
          elsif disable_maintenance
            info "Disabling maintenance mode management..."
            info "There are no database updates or config changes. This is a zero-down deployment."
            set :magento_internal_zero_down_flag, true # Set internal flag to stop db schema/data upgrades from running
            set :magento_deploy_maintenance, false     # Disable maintenance mode management since it is not neccessary
          else
            info "Maintenance mode usage will be enforced per :magento_deploy_maintenance (setting is #{fetch(:magento_deploy_maintenance).to_s})"
          end
        end
      end
    end

    desc 'Disable maintenance mode'
    task :disable do
      on release_roles :all do
        within release_path do
          execute :magento, 'maintenance:disable'
        end
      end
    end

    desc 'Displays maintenance mode status'
    task :status do
      on release_roles :all do
        within release_path do
          execute :magento, 'maintenance:status'
        end
      end
    end

    desc 'Sets maintenance mode exempt IPs'
    task 'allow-ips', :ip do |t, args|
      on release_roles :all do
        within release_path do
          execute :magento, 'maintenance:allow-ips', args[:ip]
        end
      end
    end
  end

  namespace :indexer do
    desc 'Reindex data by all indexers'
    task :reindex do
      on primary fetch(:magento_deploy_setup_role) do
        within release_path do
          execute :magento, 'indexer:reindex'
        end
      end
    end

    desc 'Shows allowed indexers'
    task :info do
      on primary fetch(:magento_deploy_setup_role) do
        within release_path do
          execute :magento, 'indexer:info'
        end
      end
    end

    desc 'Shows status of all indexers'
    task :status do
      on primary fetch(:magento_deploy_setup_role) do
        within release_path do
          execute :magento, 'indexer:status'
        end
      end
    end

    desc 'Shows mode of all indexers'
    task 'show-mode', :index do |t, args|
      on primary fetch(:magento_deploy_setup_role) do
        within release_path do
          execute :magento, 'indexer:show-mode', args[:index]
        end
      end
    end

    desc 'Sets mode of all indexers'
    task 'set-mode', :mode, :index do |t, args|
      on primary fetch(:magento_deploy_setup_role) do
        within release_path do
          execute :magento, 'indexer:set-mode', args[:mode], args[:index]
        end
      end
    end
  end
end
