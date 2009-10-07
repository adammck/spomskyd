#!/usr/bin/env ruby
# vim: noet


require "rubygems"
require "net/http"
require "mongrel"
require "rack"
require "uuid"


begin
	# try loading rubysms via a relative path
	# first, in case we're running on the trunk
	projects_dir = File.dirname(__FILE__) + "/../.."
	rubysms_path = "#{projects_dir}/rubysms/lib/rubysms.rb"
	require File.expand_path(rubysms_path)
	
rescue LoadError
	begin
	
		# couldn't load via relative
		# path, so try loading the gem
		require "rubysms"
	end
end


class SpomskyApp < SMS::App
	
	def initialize(port)
		@uuid = UUID.new()
		@subscribers = {}
		@port = port.to_i
		
		# to hold messages which were received while
		# no subscribers were available to relay to
		@pending = []
	end
	
	def start
		@rack_thread = Thread.new do
			Rack::Handler::Mongrel.run(
				method(:rack_app), :Port=>@port)
		end
		
		# add the uri of this spomsky server
		# to the screen log, for the curious
		log [
			"Started SPOMSKYd Application",
			"URI: http://localhost:#{@port}/"
		], :init
	end
	
	
	def rack_app(env)
		req = Rack::Request.new(env)
		path = req.path_info
		post = req.POST
		
		# only POST is supported
		unless req.post?
			return resp "Method not allowed", 405
		end
		
		begin
			if path == "/send"
				router.backends.each do |backend|
					begin
						dest = post["destination"]
						log("Relaying to #{dest} via #{backend.label}")
						SMS::Outgoing.new(backend, dest, post["body"]).send!
					rescue StandardError => err
						return resp "Error while sending SMS: #{err}", 500
					end
				end
				
				resp "Message Sent"
		
			elsif path == "/receive/subscribe"
				uuid = subscribe("http://#{post["host"]}:#{post["port"]}/#{post["path"]}")
				resp "Subscribed", 200, { "x-subscription-uuid" => uuid }
			
			elsif path == "/receive/unsubscribe"
				unsubscribe(post["uuid"])
				resp "Unsubscribed"
			
			# no other urls are supported
			else
				warn "Invalid Request: #{path}"
				resp "Not Found", 404
			end
		
		rescue Exception => err
			log_exception(err)
			resp("Error: #{err.message}", 500)
		end
	end
	

	# Notify each of @subscribers that an
	# incoming SMS has arrived
	def incoming(msg)
		data = {
			"source" => msg.sender.phone_number,
			"body"   => msg.text
		}
		
		# "What?! There is NO USE CASE for discarding incoming
		#  messages. Hold on to them or something!" -- Jonathan
		if @subscribers.empty?
			log("Message held (no subscribers)", :warn)
			@pending.push(msg)
		end
		
		@subscribers.each do |uuid, uri|
			begin
				res = Net::HTTP.post_form(URI.parse(uri), data)
			
			# if something goes wrong... do nothing. a client
			# has probably vanished without unsubscribing. TODO:
			# count these errors per-client, and drop after a few
			rescue StandardError => err
				log_exception(err, "Error while relaying to: #{uri}")
			end
		end
	end
	
	private
	
	# Adds a URI to the @subscribers hash, to be
	# notified (via HTTP) when an SMS arrives. Does
	# nothing if the URI is already subscribed.
	def subscribe(uri)
		log "Subscribed: #{uri}"
		
		# remote any existing subscribers to
		# the same url, to prevent duplicates
		@subscribers.each do |the_uuid, the_uri|
			@subscribers.delete(the_uuid) if\
				the_uri == uri
		end
		
		# add this subscriber
		uuid = @uuid.generate
		@subscribers[uuid] = uri
		
		# if there are any pending messages,
		# log and relay them to this subscriber
		unless @pending.empty?
			log "Relaying #{@pending.length} held messages"
			
			while msg = @pending.shift
				incoming(msg)
			end
		end
		
		uuid
	end
	
	
	# Removes a URI from the @subscribers hash, or
	# does nothing in the URI is not subscribed.
	def unsubscribe(uuid)
		log "Unubscribed: #{uuid}"
		@subscribers.delete(uuid)
	end
		
	# Return a valid Rack response using sensible default
	# arguments, so they don't have to be provided each time.
	def resp(body, code=200, more_headers = {})
		[code, {"content-type" => "text/plain"}.merge(more_headers), body]
	end
end
