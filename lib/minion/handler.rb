module Minion
  class Handler
    attr_accessor :queue, :sub, :unsub, :when, :on

    STARTFILE = "./tmp/restart.txt"

    def initialize(queue, logger = nil)
      @queue = queue
      @when = lambda { !starttimechanged? }
      @sub = lambda {}
      @unsub = lambda {}
      @on = false
      @starttime = starttime
      @logger = logger || proc { |m| puts "#{Time.now} :handler: #{m}" }
    end

    def log(msg)
      @logger.call(msg)
    end

    def should_sub?
      @when.call
    end

    def starttimechanged?
      if @starttime != (st = starttime)
        @starttime = st
        log "Start time changed"
        true
      else
        log "Start time not changed"
        false
      end 
    end

    def starttime
      File.exists?(STARTFILE) && File::Stat.new(STARTFILE).mtime
    end

    def check
      if should_sub?
        @sub.call unless @on
        log "Handler subed to #{queue}"
        @on = true
      else
        @unsub.call if @on
        log "Handler unsubed from #{queue}"
        @on = false
      end
    end

    def to_s
      "<handler queue=#{@queue} on=#{@on}>"
    end
  end
end
