require 'openssl'
require 'oauth'
require 'oauth/consumer'
require 'oauth/request_proxy/action_controller_request'
require 'oauth/request_proxy/rack_request'
# require supported signature methods since they wouldn't be autoloaded
%w{
  hmac-md5 hmac-rmd160 hmac-sha1
  md5 plaintext rsa-sha1 sha1
}.each do |method|
  require "oauth/signature/#{method.tr('-', '/')}"
end

module Gadgeteer
  def self.included(base)
    root = "."
    if base.is_a?(Class)
      base.class_eval do
        @@public_keys = Dir[File.join(root, 'config', 'certs', '*.cert')].inject({}) do |keys, file|
          cert = OpenSSL::X509::Certificate.new(File.read(file))
          pkey = OpenSSL::PKey::RSA.new(cert.public_key)
          keys.merge(File.basename(file)[0..-6] => pkey)
        end
        @@oauth_secrets = YAML.load_file(File.join(root, 'config', 'oauth_secrets.yml')) rescue {}
        cattr_accessor :public_keys, :oauth_secrets
      end
    end
    base.helper_method :open_social if base.respond_to?(:helper_method)
  end

  protected
    def public_key(key)
      @@public_keys[key || :default]
    end

    def oauth_secret(key)
      @@oauth_secrets[key || :default]
    end

    def verify_signature
      secret = if params[:xoauth_signature_publickey]
        public_key(params[:xoauth_signature_publickey])
      else
        oauth_secret(params[:oauth_consumer_key])
      end
      consumer = OAuth::Consumer.new(params[:oauth_consumer_key], secret)

      begin
        signature = OAuth::Signature.build(request) do
          # return the token secret and the consumer secret
          [nil, consumer.secret]
        end
        pass = signature.verify
      rescue OAuth::Signature::UnknownSignatureMethod => e
        logger.error "ERROR #{e}"
      end
    end

    def open_social
      @_open_social ||= params.inject({}) do |h, (k,v)|
        if k =~ /^(open_?social|os)_(.*)$/
          h.merge($2 => v)
        else
          h
        end
      end.with_indifferent_access
    end

    def os_viewer
      @_os_viewer ||= open_social.inject({}) do |h, (k,v)|
        if k =~ /^viewer_(.*)$/
          h.merge($1 => v)
        else
          h
        end
      end.with_indifferent_access
    end

    def os_owner
      @_os_owner ||= open_social.inject({}) do |h, (k,v)|
        if k =~ /^owner_(.*)$/
          h.merge($1 => v)
        else
          h
        end
      end.with_indifferent_access
    end
end