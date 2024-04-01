module Minion
  class Handler
    attr_accessor :queue, :sub, :unsub, :when, :on

    STARTFILE = "./tmp/restart.txt"

    def initialize(queue)
      @queue = queue
      @when = lambda { !starttimechanged? }
      @sub = lambda {}
      @unsub = lambda {}
      @on = false
      @starttime = starttime
    end

    def should_sub?
      @when.call
    end

    def starttimechanged?
      if @starttime != (st = starttime)
        (@starttime = st) && true
      end || false
    end

    def starttime
      File.exists?(STARTFILE) && File::Stat.new(STARTFILE).mtime
    end

    def check
      if should_sub?
        @sub.call unless @on
        @on = true
      else
        @unsub.call if @on
        @on = false
      end
    end

    def to_s
      "<handler queue=#{@queue} on=#{@on}>"
    end
  end
end
