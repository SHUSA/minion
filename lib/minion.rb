require 'uri'
require 'json' unless defined? ActiveSupport::JSON
require 'mq'
require 'bunny'
require 'minion/handler'
require 'eventmachine'

module Minion
  mattr_accessor :minion_job_handlers, :logger, :error_handler, :config_url, :channel, :amqp_url
  extend self

  def url=(url)
    @@config_url = url
  end

  def enqueue(jobs, data = {})
    raise "cannot enqueue a nil job" if jobs.nil?
    raise "cannot enqueue an empty job" if jobs.empty?

    ## jobs can be one or more jobs
    if jobs.respond_to? :shift
      queue = jobs.shift
      data["next_job"] = jobs unless jobs.empty?
    else
      queue = jobs
    end

    encoded = JSON.dump(data)
    log "send: #{queue}:#{encoded}"
    bunny.queue(queue, :durable => true, :auto_delete => false).publish(encoded)
  end

  def log(msg)
    @@logger ||= proc { |m| puts "#{Time.now} :minion: #{m}" }
    @@logger.call(msg)
  end

  def error(&blk)
    @@error_handler = blk
  end

  def logger(&blk)
    @@logger = blk
  end

  def job(queue, options = {}, &blk)
    handler = Minion::Handler.new queue, @@logger
    handler.when = options[:when] if options[:when]
    handler.unsub = lambda do
      log "unsubscribing to #{queue}"
      @@channel.queue(queue, :durable => true, :auto_delete => false).unsubscribe
    end
    handler.sub = lambda do
      log "subscribing to #{queue}"
      @@channel.queue(queue, :durable => true, :auto_delete => false).subscribe(:ack => true) do |h,m|
        return if AMQP.closing? || handler.starttimechanged?
        begin
          log "recv: #{queue}:#{m}"

          args = decode_json(m)

          result = yield(args)

          next_job(args, result)
        rescue Object => e
          raise unless error_handler
          error_handler.call(e,queue,m,h)
        end
        h.ack
        check_all
      end
    end
    @@minion_job_handlers ||= []
    at_exit { Minion.run } if @@minion_job_handlers.size == 0
    @@minion_job_handlers << handler
  end

  def decode_json(string)
    if defined? ActiveSupport::JSON
      ActiveSupport::JSON.decode string
    else
      JSON.load string
    end
  end

  def check_all
    @@minion_job_handlers.each do |h|
      unless h.check
        log "Stopping minion"
        AMQP.stop { EventMachine.stop }
      end
    end
  end

  def run
    log "Starting minion"

    Signal.trap('INT') { AMQP.stop{ EventMachine.stop } }
    Signal.trap('TERM'){ AMQP.stop{ EventMachine.stop } }

    EventMachine.run do
      AMQP.start(amqp_url) do |connection, open_ok|
        AMQP::Channel.new(connection) do |channel, open_ok|
          channel.prefetch(1)
          @@channel = channel
          check_all
        end
      end
    end
  end

  def amqp_url
    @@amqp_url ||= ENV["AMQP_URL"] || "amqp://guest:guest@localhost"
  end

  def amqp_url=(url)
    @@amqp_url = url
  end

  private

  def amqp_config
    uri = URI.parse(amqp_url)
    {
      :vhost => uri.path,
      :host => uri.host,
      :user => uri.user,
      :port => (uri.port || 5672),
      :pass => uri.password
    }
  rescue Object => e
    raise "invalid AMQP_URL: #{uri.inspect} (#{e})"
  end

  def new_bunny
    b = Bunny.new(amqp_url)
    b.start
    b
  end

  def bunny
    @@bunny ||= new_bunny
  end

  def next_job(args, response)
    queue = args.delete("next_job")
    enqueue(queue,args.merge(response)) if queue and not queue.empty?
  end

  def error_handler
    @@error_handler ||= nil
  end
end
