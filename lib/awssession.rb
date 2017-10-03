require 'awssession/version'

require 'aws-sdk-core'
require 'yaml'
require 'io/console'

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
    @session_save_lifetime = options[:session_save_lifetime] || 3600
    @session_save_filename = options[:session_save_lifetime] || "#{@profile.name}_aws-session.yaml"
  end

  def start
    load_session
    create_session
  end

  def credentials
    Aws::Credentials.new(*session_credentials)
  end

  def session_credentials
    [
      @assumed_role.credentials.access_key_id,
      @assumed_role.credentials.secret_access_key,
      @assumed_role.credentials.session_token
    ]
  end

  def create_session
    if !@session
      read_token_input
      assume_role
      save_session @assumed_role
    else
      @assumed_role = @session
    end
  end

  def read_token_input
    print 'Enter MFA token plz: '
    @token_code = STDIN.noecho(&:gets) # gets.chomp
    @token_code.chomp!
    puts ''
  end

  def sts_client
    Aws::STS::Client.new(
      access_key_id: @profile.aws_access_key_id,
      secret_access_key: @profile.aws_secret_access_key
    )
  end

  def assume_role
    @assumed_role = sts_client.assume_role(
      duration_seconds: @session_save_lifetime,
      role_arn: @profile.role_arn,
      role_session_name: 'mysession',
      serial_number: @profile.mfa_serial,
      token_code: @token_code
    )
  end

  def save_session(role)
    File.open(@session_save_filename, 'w') { |f| f.write role.to_yaml } # Store
  end

  def load_session
    return unless File.file?(@session_save_filename)
    @session = YAML.load_file(@session_save_filename) # Load
    if Time.now > @session.credentials.expiration
      puts 'Session credentials expired. Removing obsolete sessions.yaml file'
      @session = nil
      File.delete(@session_save_filename)
    else
      puts 'Found valid session credentials.'
    end
  end
end
