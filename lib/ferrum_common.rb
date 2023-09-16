require "ferrum"
module FerrumCommon

  module Common

    private def mhtml browser, timeout, mtd, msg = nil
      Timeout.timeout(timeout){ yield }
    rescue Timeout::Error
      browser.mhtml path: "temp.mhtml"
      STDERR.puts "dumped to ./temp.mhtml"
      $!.backtrace.reject!{ |_| _[/\/gems\/concurrent-ruby-/] }
      $!.backtrace.reject!{ |_| _[/\/gems\/ferrum-/] }
      raise Timeout::Error, "#{$!.to_s} after #{timeout} sec in #{mtd}#{" (#{msg.respond_to?(:call) ? msg.call : msg})" if msg}"
    end

    def until_true timeout, msg = nil
      mhtml self, timeout, __method__, msg do
        begin
          yield
        rescue Ferrum::NodeNotFoundError
          redo
        end or (sleep timeout*0.1; redo)
      end
    end

    def until_one type, selector, timeout
      t = nil
      mhtml self, timeout, __method__, ->{ "expected exactly one node for #{type} #{selector.inspect}, got #{t ? t.size : "none"}" } do
        t = begin
          public_method(type).call selector
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
  def self.process_mhtml mht
    scanner = ::StringScanner.new mht
    fail scanner.peek(100).inspect unless scanner.scan(/\AFrom: <Saved by Blink>\r
Snapshot-Content-Location: \S+\r
Subject:(?: \S+\r\n)+Date: [A-Z][a-z][a-z], \d\d? [A-Z][a-z][a-z] 20\d\d \d\d:\d\d:\d\d -0000\r
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
        puts "trash #{$'.size}"
        reps.push [prev-delimeter.size-2, scanner.pos-delimeter.size-4, "", ""]
      when /\A\r\nContent-Type: text\/html\r
Content-ID: <frame-[A-Z0-9]{32}@mhtml\.blink>\r
Content-Transfer-Encoding: quoted-printable\r
Content-Location: \S+\r\n\r\n/
        puts "html #{$'.size}"
        header = $&
        t = $'.gsub(/=([0-9A-F][0-9A-F])/){ fail $1 unless "3D" == $1 || "20" == $1 || "0A" == $1 unless "80" <= $1; $1.hex.chr }.gsub("=\r\n", "")
        puts "unpacked #{t.size}"
        html = ::Nokogiri::HTML t#.force_encoding "utf-8"

        puts ".to_s.size #{html.to_s.size}"

        html.xpath("//*[not(*)]").group_by(&:name).
          map{ |_, g| [_, g.map(&:to_s).map(&:size).reduce(:+)] }.
          sort_by(&:last).reverse.take(5).each &method(:p)

        if block_given?
          yield html
          puts "yielded"
          puts "yield #{html.to_s.size}"
        end

        reps.push [prev, scanner.pos-delimeter.size-4, header, html.to_s, true, :html]
      when /\A\r\nContent-Type: text\/css\r
Content-Transfer-Encoding: quoted-printable\r
Content-Location: \S+\r\n\r\n/
        puts "css > #{$'.size}"
        header = $&
        css = $'.gsub(/=([0-9A-F][0-9A-F])/){ fail $1 unless "3D" == $1 || "20" == $1 || "0A" == $1 unless "80" <= $1; $1.hex.chr }.gsub("=\r\n", "")
        css.gsub!(/[\r\n]+/, "\n")

        puts "css < #{css.size}"
        reps.push [prev, scanner.pos-delimeter.size-4, header, css, true, :css]

      when /\A\r\nContent-Type: image\/(webp|png|gif|jpeg)\r
Content-Transfer-Encoding: base64\r
Content-Location: \S+\r\n\r\n/
        puts "#{$1} #{$'.size}"
      when /\A\r\nContent-Type: image\/svg\+xml\r
Content-Transfer-Encoding: quoted-printable\r
Content-Location: \S+\r\n\r\n/
        puts "svg #{$'.size}"
      else
        puts doc[0..300]
        fail
      end
      fail unless scanner.charpos == prev = scanner.pos
    end

    p is = reps.map.with_index{ |(_, _, _, _, _, type), i| i if :html == type }.compact
    p cs = reps.map.with_index{ |(_, _, _, _, _, type), i| i if :css == type }.compact
    cs.each_cons(2){ |i,j| fail unless i+1==j }
    fail unless is == [cs[0]-1]
    File.write "temp.htm", reps[is[0]][3]
    puts "css > #{File.size "temp.css"}"
    File.open("temp.css", "w"){ |f| cs.each{ |i| f.puts reps[i][3] } }
    system "uncss temp.htm -s temp.css -o out.css"
    puts "css < #{File.size "out.css"}"
    reps[cs[0]][1] = reps[cs[-1]][1]
    reps[cs[0]+1..cs[-1]] = []
    reps[cs[0]][3] = File.read "out.css"

    reps.reverse_each do |from, to, header, str, qp|
      str = qp ?
        header + str.gsub("=", "=3D").
          b.gsub(/[\x80-\xFF]/n){ |_| "=%02X" % _.ord }.
          gsub(/.{73}[^=][^=](?=.)/, "\\0=\r\n") :
        header + str.gsub("\n", "\r\n")
      p [str.size, "to - from = #{to - from}"]
      mht[from...to] = str
    end
    p ::File.write "temp.mht", mht
    puts "OK"
  end

end
