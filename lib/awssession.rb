require 'awssession/version'

require 'aws-sdk-core'
require 'yaml'
require 'io/console'
require 'time'

# AWS Session creation with profile
# Structure of options[:profile]
# {
#    'name' => <name>,
#    'region' => <region>
#    'role_arn' => <role_arn>
#    'aws_access_key_id' => <aws_access_key_id>
#    'aws_secret_access_key' => <aws_secret_access_key>
#    'mfa_serial' => <mfa_serial>
# }
# Can be fetched with AWSConfig[profile_name] if .aws/config
#
class AwsSession
  def initialize(options)
    @profile = options[:profile]
    @sts_lifetime = options[:sts_lifetime] || 129_600
    @sts_filename = options[:sts_filename] || "#{@profile.name}_aws-sts-session.yaml"
    @role_lifetime = options[:role_lifetime] || 3_600
    @role_filename = options[:role_filename] || "#{@profile.name}_aws-role-session.yaml"
    @session_save_path = options[:session_save_path] || "#{Dir.home}/.aws/cache"
    @debug = options[:debug] || 0
  end

  def start
    load_session
    create_session
  end

  def load_session
    load_role_session if File.file?("#{@session_save_path}/#{@role_filename}")
    load_sts_session if @role_session.nil? && File.file?("#{@session_save_path}/#{@sts_filename}")
  end

  def load_role_session
    @role_session = YAML.load_file("#{@session_save_path}/#{@role_filename}") # Load
    if Time.now > @role_session.credentials.expiration
      # or soooooooon !
      puts 'Role session credentials expired. Removing obsolete role session file' if @debug > 0
      @role_session = nil
      File.delete("#{@session_save_path}/#{@role_filename}")
    elsif @debug > 0
      puts 'Found valid role session credentials.'
    end
  end

  def load_sts_session
    @sts_session = YAML.load_file("#{@session_save_path}/#{@sts_filename}") # Load
    if Time.now > @sts_session.credentials.expiration
      # or soooooooon !
      puts 'STS session credentials expired. Removing obsolete sts session file' if @debug > 0
      @sts_session = nil
      File.delete("#{@session_save_path}/#{@sts_filename}")
    elsif @debug > 0
      puts 'Found valid sts session credentials.'
    end
  end

  def create_session
    if @role_session.nil? && @sts_session.nil?
      read_token_input
      sts_session_token
      save_session @sts_filename, @sts_session
    end
    return unless @role_session.nil?
    assume_role
    save_session @role_filename, @role_session
  end

  def read_token_input
    print 'Enter AWS MFA token: '
    @token_code = STDIN.noecho(&:gets)
    @token_code.chomp!
    puts ''
  end

  def sts_session_token
    sts_client = Aws::STS::Client.new(
      access_key_id: @profile.aws_access_key_id,
      secret_access_key: @profile.aws_secret_access_key
    )
    @sts_session = sts_client.get_session_token(
      duration_seconds: @sts_lifetime,
      serial_number: @profile.mfa_serial,
      token_code: @token_code
    )
  end

  def assume_role
    sts_client = Aws::STS::Client.new(
      access_key_id: @sts_session.credentials.access_key_id,
      secret_access_key: @sts_session.credentials.secret_access_key,
      session_token: @sts_session.credentials.session_token
    )
    @role_session = sts_client.assume_role(
      duration_seconds: @role_lifetime,
      role_arn: @profile.role_arn,
      role_session_name: "#{ENV['USER']}-#{Time.now.utc.iso8601.tr!('-:', '_')}"
    )
  end

  def save_session(file, session)
    FileUtils.mkdir_p(@session_save_path)
    File.open("#{@session_save_path}/#{file}", 'w') { |f| f.write session.to_yaml }
  end

  def credentials
    Aws::Credentials.new(*session_credentials)
  end

  def session_credentials
    [
      @role_session.credentials.access_key_id,
      @role_session.credentials.secret_access_key,
      @role_session.credentials.session_token
    ]
  end
end
