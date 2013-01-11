require 'rails'
module DragonflyRails
  class Railtie < ::Rails::Railtie
    config.dragonfly_rails = DragonflyRails
    initializer 'dragonfly_rails.extend_dragonfly', :before => 'dragonfly_rails.active_record' do
      datastore_type = (Rails.env.production? || Rails.env.staging?) ? 's3' : 'fs'
      require File.expand_path("../data_storage/#{datastore_type}", __FILE__)
    end
    initializer 'dragonfly_rails.active_record' do
      ::ActiveRecord::Base.send(:extend, ::DragonflyRails::Dragonfly::ActiveModelExtensions::ClassMethods)
      ::ActiveRecord::Base.send(:include, ::DragonflyRails::CustomPathExtension)
    end
    initializer 'dragonfly_rails.load_extension', :after => 'dragonfly_rails.active_record' do
      if ::Rails.configuration.dragonfly_rails.assets_path == :default
        ::Rails.configuration.dragonfly_rails.assets_path = Rails.root.join('public','assets')
      end
      config = ::Rails.configuration.dragonfly_rails
      @app = ::Dragonfly[:images]
      @app.configure_with(:imagemagick)
      @app.configure do |c|
        c.protect_from_dos_attacks = config.protect_from_dos_attacks
        c.secret = config.security_key
        c.log = ::Rails.logger
        if false and (::Rails.env.production? || ::Rails.env.staging?) # not sure why we are forcing S3 with heroku
          @app.configure_with(:heroku, config.storage_options)
        else
          if c.datastore.is_a?(::Dragonfly::DataStorage::FileDataStore)
            c.datastore.root_path = config.assets_path.to_s
            c.datastore.server_root = ::Rails.root.join('public').to_s
          end
        end
        c.url_format = "/#{config.route_path}/:job/:basename.:format"
        c.analyser.register(::Dragonfly::Analysis::FileCommandAnalyser)
      end
      @app.define_macro(::ActiveRecord::Base, :image_accessor)
    end

    initializer 'load assets dispatcher', :after => 'dragonfly_rails.load_extension' do |app|
      app.middleware.insert_after ::Rack::Lock, ::Dragonfly::Middleware, :images
    end

    initializer 'dragonfly filesistem cache', :after => 'load assets dispatcher' do |app|
      if ::Dragonfly[:images].datastore.is_a?(::Dragonfly::DataStorage::FileDataStore)
        begin
          require 'uri'
          require 'rack/cache'
          Rails.application.middleware.insert_before 'Dragonfly::Middleware', 'Rack::Cache', {
            :verbose     => true,
            :metastore   => URI.encode("file:#{Rails.root}/tmp/dragonfly/cache/meta"), # URI encoded because Windows
            :entitystore => URI.encode("file:#{Rails.root}/tmp/dragonfly/cache/body")  # has problems with spaces
          }
        rescue LoadError => e  
          app.log.warn("Warning: couldn't find rack-cache for caching dragonfly content")
        end
      end
    end

    # railtie code goes here
  end
end
