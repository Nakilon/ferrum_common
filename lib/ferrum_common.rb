require "ferrum"
module FerrumCommon

  module Common

    private def yield_with_timeout browser, timeout, mtd, msg = nil
      Timeout.timeout(timeout){ yield }
    rescue Timeout::Error
      browser.mhtml path: "temp.mhtml"
      STDERR.puts "dumped to ./temp.mhtml"
      $!.backtrace.reject!{ |_| _[/\/gems\/concurrent-ruby-/] }
      $!.backtrace.reject!{ |_| _[/\/gems\/ferrum-/] }
      raise Timeout::Error, "#{$!.to_s} after #{timeout} sec in #{mtd}#{" (#{msg.respond_to?(:call) ? msg.call : msg})" if msg}"
    end

    def until_true timeout, msg = nil
      yield_with_timeout self, timeout, __method__, msg do
        begin
          yield
        rescue Ferrum::NodeNotFoundError
          redo
        end or (sleep timeout * 0.1; redo)
      end
    end

    def find_any type, selector, timeout
      Timeout.timeout timeout do
        t = public_method(type).call selector
        return t unless t.empty?
        sleep timeout * 0.1
        redo
      end
    rescue Timeout::Error
    end

    def until_one type, selector, timeout, node = nil
      t = nil
      yield_with_timeout self, timeout, __method__, ->{ "expected exactly one node for #{type} #{selector.inspect}, got #{t ? t.size : "none"}" } do
        t = begin
          public_method(type).call selector, within: node
        end
        unless 1 == t.size
          sleep timeout * 0.1
          redo
        end
      end
      t.first
    end

    def abort msg_or_cause
      puts msg_or_cause
      puts (msg_or_cause.respond_to?(:full_message) ? msg_or_cause.full_message : Thread.current.backtrace)
      mhtml path: "temp.mhtml"
      STDERR.puts "dumped to ./temp.mhtml"
      Kernel.abort msg_or_cause.to_s
    end

  end
  Ferrum::Page.include Common
  Ferrum::Frame.include Common

  if "darwin" == Gem::Platform.local.os
    require "browser_reposition"
    Ferrum::Browser.include Common, BrowserReposition
    def self.new **_
      Ferrum::Browser.new(**_).tap(&:reposition)
    end
  else
    Ferrum::Browser.include Common
    def self.new **_
      Ferrum::Browser.new **_
    end
  end

  # https://datatracker.ietf.org/doc/html/rfc2557
  # https://en.wikipedia.org/wiki/Quoted-printable
  # require "strscan"
  require "nokogiri"  # Oga crashes on vk charset
  def self.process_mhtml
    scanner = ::StringScanner.new(mht = ARGF.read)
    fail scanner.peek(400).inspect unless scanner.scan(/\AFrom: <Saved by Blink>\r
Snapshot-Content-Location: \S+\r
Subject:(?: \S.*\r\n)+Date: [A-Z][a-z][a-z], \d\d? [A-Z][a-z][a-z] 20\d\d \d\d:\d\d:\d\d -0000\r
MIME-Version: 1\.0\r
Content-Type: multipart\/related;\r
\ttype="text\/html";\r
\tboundary="(----MultipartBoundary--[a-zA-Z0-9]{42}----)"\r\n\r\n\r\n--\1/)
    delimeter = scanner[1]
    fail unless scanner.charpos == prev = scanner.pos
    reps = []
    while s = scanner.search_full(::Regexp.new(delimeter), true, true)
      doc = s[0...-delimeter.size-4]
      case doc
      when /\A\r\nContent-Type: text\/html\r
Content-ID: <frame-[A-Z0-9]{32}@mhtml\.blink>\r
Content-Transfer-Encoding: quoted-printable\r
Content-Location: chrome-error:\/\/chromewebdata\/\r\n\r\n/,
           /\A\r\nContent-Type: text\/html\r
Content-ID: <frame-[A-Z0-9]{32}@mhtml\.blink>\r
Content-Transfer-Encoding: quoted-printable\r\n\r\n/
        STDERR.puts "trash #{$'.size}"
        reps.push [prev-delimeter.size-2, scanner.pos-delimeter.size-4, "", ""]
      when /\A\r\nContent-Type: text\/html\r
Content-ID: <frame-[A-Z0-9]{32}@mhtml\.blink>\r
Content-Transfer-Encoding: quoted-printable\r
Content-Location: \S+\r\n\r\n/
        STDERR.puts "html #{$'.size}"
        header = $&
        t = $'.gsub(/=([0-9A-F][0-9A-F])/){ fail $1 unless "3D" == $1 || "20" == $1 || "0A" == $1 unless "80" <= $1; $1.hex.chr }.gsub("=\r\n", "")
        STDERR.puts "unpacked #{t.size}"
        html = ::Nokogiri::HTML t#.force_encoding "utf-8"

        STDERR.puts ".to_s.size #{html.to_s.size}"

        html.xpath("//*[not(*)]").group_by(&:name).
          map{ |_, g| [_, g.map(&:to_s).map(&:size).reduce(:+)] }.
          sort_by(&:last).reverse.take(5).each{ |_| STDERR.puts _.inspect }

        if block_given?
          yield html
          STDERR.puts "yielded"
          STDERR.puts "yield #{html.to_s.size}"
        end

        reps.push [prev, scanner.pos-delimeter.size-4, header, html.to_s, true, :html]
      when /\A\r\nContent-Type: text\/css\r
Content-Transfer-Encoding: quoted-printable\r
Content-Location: \S+\r\n\r\n/
        STDERR.puts "css > #{$'.size}"
        header = $&
        css = $'.gsub(/=([0-9A-F][0-9A-F])/){ fail $1 unless "3D" == $1 || "20" == $1 || "0A" == $1 unless "80" <= $1; $1.hex.chr }.gsub("=\r\n", "")
        css.gsub!(/[\r\n]+/, "\n")

        STDERR.puts "css < #{css.size}"
        reps.push [prev, scanner.pos-delimeter.size-4, header, css, true, :css]

      when /\A\r\nContent-Type: image\/(webp|png|gif|jpeg)\r
Content-Transfer-Encoding: base64\r
Content-Location: https:\S+\r\n\r\n/
        STDERR.puts "#{$1} #{$'.size}"
      when /\A\r\nContent-Type: binary\/octet-stream\r
Content-Transfer-Encoding: base64\r
Content-Location: https:\/\/\S+\r\n\r\n/
        STDERR.puts "binary #{$'.size}"
      when /\A\r\nContent-Type: image\/svg\+xml\r
Content-Transfer-Encoding: quoted-printable\r
Content-Location: https:\S+\r\n\r\n/
        STDERR.puts "svg #{$'.size}"
      when /\A\r\nContent-Type: image\/gif\r
Content-ID: <frame-[0-9A-F]{32}@mhtml\.blink>\r
Content-Transfer-Encoding: base64\r
Content-Location: https:\S+\r\n\r\n/
        STDERR.puts "gif #{$'.size}"
      else
        STDERR.puts doc[0..300]
        fail
      end
      fail unless scanner.charpos == prev = scanner.pos
    end

    is = reps.map.with_index{ |(_, _, _, _, _, type), i| i if :html == type }.compact
    STDERR.puts is.inspect
    cs = reps.map.with_index{ |(_, _, _, _, _, type), i| i if :css == type }.compact
    STDERR.puts cs.inspect
    cs.each_cons(2){ |i,j| fail unless i+1==j }
    fail unless is == [cs[0]-1]
    File.write "temp.htm", reps[is[0]][3]
    STDERR.puts "css > #{File.size "temp.css"}"
    File.open("temp.css", "w"){ |f| cs.each{ |i| f.puts reps[i][3] } }
    system "uncss temp.htm -s temp.css -o out.css"
    STDERR.puts "css < #{File.size "out.css"}"
    reps[cs[0]][1] = reps[cs[-1]][1]
    reps[cs[0]+1..cs[-1]] = []
    reps[cs[0]][3] = File.read "out.css"

    reps.reverse_each do |from, to, header, str, qp|
      str = qp ?
        header + str.gsub("=", "=3D").
          b.gsub(/[\x80-\xFF]/n){ |_| "=%02X" % _.ord }.
          gsub(/.{73}[^=][^=](?=.)/, "\\0=\r\n") :
        header + str.gsub("\n", "\r\n")
      STDERR.puts [str.size, "to - from = #{to - from}"].inspect
      mht[from...to] = str
    end
    puts mht
    STDERR.puts "OK"
  end

end
