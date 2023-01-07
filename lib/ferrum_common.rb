require "ferrum"
module FerrumCommon
  def self.new **_
    Ferrum::Browser.new(**_).tap do |browser|
      require "browser_reposition"
      browser.extend(BrowserReposition).reposition
      browser.define_singleton_method :redo_until_true do |timeout, msg = nil, &block|
        Timeout.timeout timeout do
          begin
            block.call
          rescue Ferrum::NodeNotFoundError
            redo
          end or (sleep timeout*0.1; redo)
        end
      rescue Timeout::Error
        browser.mhtml path: "temp.mhtml"
        $!.backtrace.reject!{ |_| _[/\/gems\/concurrent-ruby-/] }
        $!.backtrace.reject!{ |_| _[/\/gems\/ferrum-/] }
        raise Timeout::Error, "#{$!.to_s} in redo_until_true #{" (#{msg})" if msg}"
      end
      browser.define_singleton_method :abort do |msg|
        Browser.mhtml path: "temp.mhtml"
        puts Thread.current.backtrace
        abort msg
      end
    end
  end
end
