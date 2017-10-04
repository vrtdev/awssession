#!/usr/bin/env ruby

require 'awssession'

require 'aws-sdk-ssm'
require 'aws_config'
require 'pp'

profile_name = ARGV[0]
profile = AWSConfig[profile_name]
profile['name'] = profile_name

awssession = AwsSession.new(profile: profile)
awssession.start

ssm = Aws::SSM::Client.new(credentials: awssession.credentials)

ssm.describe_parameters.parameters.each do |p|
  puts "Parameter Name: #{p.name}."
end

puts 'Get Parameter by Path, 2 results'
pp ssm.get_parameters_by_path(
  path: '/',
  recursive: true,
  max_results: 2
)
