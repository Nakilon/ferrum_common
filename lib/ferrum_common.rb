require "ferrum"
module FerrumCommon

  module Common

    def self.mhtml browser, timeout, mtd, msg = nil
      Timeout.timeout(timeout){ yield }
    rescue Timeout::Error
      browser.mhtml path: "temp.mhtml"
      $!.backtrace.reject!{ |_| _[/\/gems\/concurrent-ruby-/] }
      $!.backtrace.reject!{ |_| _[/\/gems\/ferrum-/] }
      raise Timeout::Error, "#{$!.to_s} after #{timeout} sec in #{mtd}#{" (#{msg.respond_to?(:call) ? msg.call : msg})" if msg}"
    end

    def until_true timeout, msg = nil
      Module.nesting.first.mhtml self, timeout, __method__, msg do
        begin
          yield
        rescue Ferrum::NodeNotFoundError
          redo
        end or (sleep timeout*0.1; redo)
      end
    end

    def until_one type, selector, timeout
      t = nil
      Module.nesting.first.mhtml self, timeout, __method__, ->{ "expected exactly one node for #{type} #{selector.inspect}, got #{t ? t.size : "none"}" } do
        t = begin
          public_method(type).call selector
        rescue Ferrum::NodeNotFoundError
          sleep timeout * 0.1
          redo
        end
        unless 1 == t.size
          sleep timeout * 0.1
          redo
        end
      end
      t.first
    end

    def abort msg_or_cause
      # puts (msg_or_cause.respond_to?(:backtrace) ? msg_or_cause : Thread.current).backtrace
      puts (msg_or_cause.respond_to?(:full_message) ? msg_or_cause.full_message : Thread.current.backtrace)
      mhtml path: "temp.mhtml"
      puts "dumped to ./temp.mhtml"
      Kernel.abort msg_or_cause.to_s
    end

  end
  Ferrum::Page.include Common
  Ferrum::Frame.include Common

  require "browser_reposition"
  Ferrum::Browser.include Common, BrowserReposition
  def self.new **_
    Ferrum::Browser.new(**_).tap(&:reposition)
  end

end
