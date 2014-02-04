require 'couchrest'
require 'json'

module Tapicero
  class UserDatabase

    def initialize(user_id)
      @db = couch.database(config.options[:db_prefix] + user_id)
    end

    def prepare
      create
      secure
      add_design_docs
      Tapicero.logger.info "Prepared storage " + db.name
    end

    def create
      retry_request_once "Creating database" do
        create_db
      end
    end

    def secure(security = nil)
      security ||= config.options[:security]
      # let's not overwrite if we have a security doc already
      return if secured? && !Tapicero::FLAGS.include?('--overwrite-security')
      retry_request_once "Writing security to" do
        Tapicero.logger.debug security.to_json
        CouchRest.put security_url, security
      end
    end

    def add_design_docs
      pattern = BASE_DIR + 'designs' + '*.json'
      Tapicero.logger.debug "Looking for design docs in #{pattern}"
      Pathname.glob(pattern).each do |file|
        retry_request_once "Uploading design doc to" do
          upload_design_doc(file)
        end
      end
    end

    def upload_design_doc(file)
      CouchRest.put design_url(file.basename('.json')), JSON.parse(file.read)
    rescue RestClient::Conflict
    end


    def destroy
      retry_request_once "Deleting database" do
        delete_db
      end
    end

    protected

    def create_db
      db.create! || db.info
    end

    def delete_db
      db.delete! if db
    rescue RestClient::ResourceNotFound  # no database found
    end

    def retry_request_once(action)
      second_try ||= false
      Tapicero.logger.debug "#{action} #{db.name}"
      yield
    rescue RestClient::Exception => exc
      if second_try
        log_error "#{action} #{db.name} failed twice due to:", exc
      else
        log_error "#{action} #{db.name} failed due to:", exc
        sleep 5
        second_try = true
        retry
      end
    end

    def log_error(message, exc)
      Tapicero.logger.warn message if message
      Tapicero.logger.warn exc.class.name + ': ' + exc.to_s
      Tapicero.logger.debug exc.backtrace.join("\n")
    end

    def secured?
      retry_request_once "Checking security of" do
        CouchRest.get(security_url).keys.any?
      end
    end

    def security_url
      db.root + "/_security"
    end

    def design_url(doc_name)
      db.root + "/_design/#{doc_name}"
    end

    attr_reader :db

    def couch
      @couch ||= CouchRest.new(config.couch_host)
    end

    def config
      Tapicero.config
    end

  end
end
