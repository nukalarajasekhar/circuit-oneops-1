#
# Cookbook Name:: netscaler
# Recipe:: add_lbvserver
#
# Copyright 2016, Walmart Stores, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'excon'

# cleanup old ones if they change vport or vprotocol (name changes)
node.cleanup_loadbalancers.each do |lb|
  delete_lb(lb)
end

lbmethod = node.workorder.rfcCi.ciAttributes.lbmethod.upcase

# use previous dns_record attr for ip of cloud-level lb only if cloud vips were previously created
ip = nil
if node.workorder.rfcCi.ciAttributes.has_key?("dns_record") &&
   node.workorder.rfcCi.ciBaseAttributes.has_key?("create_cloud_level_vips") &&
   node.workorder.rfcCi.ciBaseAttributes.create_cloud_level_vips == "true"
  ip = node.workorder.rfcCi.ciAttributes.dns_record
end

cloud_name = node.workorder.cloud.ciName
cloud_service = node[:workorder][:services][:lb][cloud_name]
# servers
servers = []
computes = node.workorder.payLoad.DependsOn.select { |d| d[:ciClassName] =~ /Compute/ }
computes.each do |c|
  servers.push c['ciAttributes']['private_ip']
end

cloud_name = node[:workorder][:cloud][:ciName]
service = node[:workorder][:services][:lb][cloud_name][:ciAttributes]
Chef::Log.info("endpoint: #{service[:endpoint]}")
node.set['lb_dns_name'] = service[:endpoint].gsub('https://','').gsub(/:\d+/,'')

conn = Excon.new(service[:endpoint], 
#  :user => service[:username], 
#  :password => service[:password], 
  :ssl_verify_peer => false)
  
node.loadbalancers.each do |lb_def|

  lb_name = lb_def[:name]
  iport = lb_def[:iport]
  backend = nil
  frontend = nil
  Chef::Log.info("lb name: "+lb_name)

  # backend
  lb_method = node.lb.lbmethod
  iprotocol = lb_def[:iprotocol].upcase

  Chef::Log.info("/backend/#{lb_name}")
  response = conn.request(:method => :get, :path => "/backend/#{lb_name}")      
  puts "response: #{response.inspect}"
  if response.status == 200 
    backend = JSON.parse(response.body)
  end 
  if backend.nil?
    backend = { 
      :balance => lb_method,
      :servers => servers
    }

    response = conn.request(:method => :post,
      :path => "/backend/#{lb_name}", :body => JSON.dump(backend))
            
    puts "new backend: #{response.inspect}"
  else
    puts "existing backend: #{backend.inspect}"
  end
  
  
  # frontend
  response = conn.request(:method => :get, :path => "/frontend/#{lb_name}")      
  puts "response: #{response.inspect}"
  if response.status == 200 
    frontend = JSON.parse(response.body)
  end 
  if frontend.nil?
    frontend = { 
      :port => lb_def[:vport],
    }

    frontend = JSON.parse(conn.request(:method => :post,
      :path => "/frontend/#{lb_name}", :body => JSON.dump(frontend)).body)
            
    puts "new frontend: #{frontend.inspect}"
  else
    puts "existing frontend: #{frontend.inspect}"
  end
  
end
