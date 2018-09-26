#!/usr/bin/ruby

require 'json'
require 'net/http'
require 'open3'
require 'openssl'

# Install terminal notifier gem if you want it.
begin
  require 'terminal-notifier'
rescue LoadError
  class TerminalNotifier
    def self.notify(*)
    end
    def self.remove(*)
    end
  end
end

class OctoboxNotification
  attr_reader :data

  def initialize(data)
    @data = data
  end

  def id
    data.fetch('id')
  end

  def gh_id
    data.fetch('github_id')
  end

  def title
    data.fetch('subject').fetch('title')
  end

  def unread?
    data.fetch('unread')
  end

  def read?
    !unread?
  end

  def type
    data.fetch('subject').fetch('type')
  end

  def short_type
    type.each_char.select { |c| c.upcase == c }.join
  end

  def repo_name
    data.fetch('repo').fetch('name')
  end

  def state
    data.fetch('subject').fetch('state')
  end

  def icon
    case type
    when 'Issue'
      "!\u20DD"
    when 'PullRequest'
      '⭠ '
    when 'Commit'
      '⏀'
    when 'Release'
      '🏷'
    when 'RepositoryVulnerabilityAlert'
      '⚠︎'
    else
      raise "Unkown type: #{type}"
    end
  end

  def color
    case state
    when 'open'
      "\x1b[1;32m"
    when 'merged'
      "\x1b[1;35m"
    when 'closed'
      "\x1b[31m"
    else
      ''
    end
  end

  def color_icon
    "#{color}#{icon}\x1b[0m"
  end

  def url
    data.fetch('web_url')
  end

  def menu_string
    "#{color_icon} #{repo_name} #{title}"
  end
end

class OctoboxBitbar
  IMAGE = "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"
  TMP_DATA_FILE = '/tmp/octobox-bitbar-ids.json'.freeze
  MARK_READ_AND_OPEN = File.join(__dir__, 'octobox_mark_read_and_open.rb')
  ARCHIVE = File.join(__dir__, 'octobox_archive.rb')

  def set_notification
    if current_ids.empty?
      TerminalNotifier.remove(:octobox)
    elsif notification_changed && unread_notifications.size == 1
      notification = unread_notifications.first
      TerminalNotifier.notify(
        notification.title,
        title: "Octobox",
        subtitle: "New #{notification.type} in #{notification.repo_name}",
        group: :octobox,
        execute: "#{MARK_READ_AND_OPEN} '#{notification.id}' '#{notification.url}'",
        appIcon: "data:image/png;base64,#{IMAGE}",
      )
    elsif notification_changed
      TerminalNotifier.notify(
        pluralize(current_ids.size, "unread item"),
        title: 'Octobox',
        subtitle: 'Pending review',
        group: :octobox,
        execute: 'open https://octobox.shopify.io/',
        appIcon: "data:image/png;base64,#{IMAGE}",
      )
    end
  end

  def to_s
    msg = [
      "#{unread_notifications.size}/#{notifications.size}| templateImage=#{IMAGE}",
      "---",
      "View all in Octobox| href=https://octobox.shopify.io/",
      "Refresh| refresh=true",
      "---",
    ]

    msg.concat(
      unread_notifications.flat_map do |notification|
        [
          "#{notification.menu_string}| bash=#{MARK_READ_AND_OPEN} param1=#{notification.id} param2=#{notification.url} terminal=false refresh=true",
          "--Archive| bash=#{ARCHIVE} param1=#{notification.id} terminal=false refresh=true",
        ]
      end
    )

    if read_notifications.any?
      msg.concat([
        "---",
        "Archive all read notifications| bash=#{ARCHIVE} param1=#{read_notifications.map(&:id).join(',')} terminal=false refresh=true",
      ])
      msg.concat(
        read_notifications.flat_map do |notification|
          [
            "#{notification.menu_string}| href=#{notification.url}",
            "--Archive| bash=#{ARCHIVE} param1=#{notification.id} terminal=false refresh=true",
          ]
        end
      )
    end
    msg.join("\n")
  end

  private

  def pluralize(n, str)
    "#{n} #{str}#{'s' unless n == 1}"
  end

  def token
    return @token if defined?(@token)
    @token, _, t = Open3.capture3('security', 'find-generic-password', '-w', '-l', 'octobox-token')
    raise 'Cannot retrieve token' unless t.success?
    @token
  end

  def notifications
    begin_for_retry do
      @notifications ||= Net::HTTP.start('octobox.shopify.io', 443, use_ssl: true) do |http|
        resp = http.get('/notifications.json', 'Authorization' => "Bearer #{token}")
        raise 'Cannot access octobox' unless resp.code.to_i == 200

        JSON.parse(resp.body).fetch('notifications').map { |data| OctoboxNotification.new(data) }
      end
    end.retry_after(OpenSSL::SSL::SSLError, retries: 3)
  end

  def unread_notifications
    notifications.select(&:unread?)
  end

  def read_notifications
    notifications.select(&:read?)
  end

  def current_ids
    unread_notifications.map(&:gh_id).sort
  end

  def previous_ids
    return @previous_ids if defined?(@previous_ids)
    @previous_ids = begin
      JSON.parse(File.read(TMP_DATA_FILE))
    rescue Exception => _
      []
    end
    File.write(TMP_DATA_FILE, JSON.generate(current_ids))
    @previous_ids
  end

  def notification_changed
    current_ids != previous_ids
  end

  def begin_for_retry(&block_that_might_raise)
    Retrier.new(block_that_might_raise)
  end

  class Retrier
    def initialize(block_that_might_raise)
      @block_that_might_raise = block_that_might_raise
    end

    def retry_after(exception = StandardError, retries: 1, &before_retry)
      @block_that_might_raise.call
    rescue exception => e
      raise if (retries -= 1) < 0
      if before_retry
        if before_retry.arity == 0
          yield
        else
          yield e
        end
      end
      retry
    end
  end

  private_constant :Retrier
end

begin
  puts OctoboxBitbar.new.tap(&:set_notification)
rescue StandardError => e
  puts "💥 #{e.message}| image=#{OctoboxBitbar::IMAGE}"
  puts "---"
  puts "#{e.class}: #{e.message}"
  puts e.backtrace
end
