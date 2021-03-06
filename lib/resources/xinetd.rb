# encoding: utf-8
# author: Christoph Hartmann
# author: Dominik Richter

require 'utils/parser'

module Inspec::Resources
  class XinetdConf < Inspec.resource(1) # rubocop:disable Metrics/ClassLength
    name 'xinetd_conf'
    desc 'Xinetd services configuration.'
    example "
      describe xinetd_conf.services('chargen') do
        its('socket_types') { should include 'dgram' }
      end

      describe xinetd_conf.services('chargen').socket_types('dgram') do
        it { should be_disabled }
      end
    "

    include XinetdParser

    def initialize(conf_path = '/etc/xinetd.conf', opts = {})
      @conf_path = conf_path
      @params = opts[:params] unless opts[:params].nil?
      @filters = opts[:filters] || ''
      @contents = {}
    end

    def to_s
      "Xinetd config #{@conf_path}"
    end

    def services(condition = nil)
      condition.nil? ? params['services'].keys : filter(service: condition)
    end

    def ids(condition = nil)
      condition.nil? ? services_field('id') : filter(id: condition)
    end

    def socket_types(condition = nil)
      condition.nil? ? services_field('socket_type') : filter(socket_type: condition)
    end

    def types(condition = nil)
      condition.nil? ? services_field('type') : filter(type: condition)
    end

    def wait(condition = nil)
      condition.nil? ? services_field('wait') : filter(wait: condition)
    end

    def disabled?
      filter(disable: 'no').services.empty?
    end

    def enabled?
      filter(disable: 'yes').services.empty?
    end

    def params
      return @params if defined?(@params)
      return @params = {} if read_content.nil?
      flat_params = parse_xinetd(read_content)
      @params = { 'services' => {} }
      flat_params.each do |k, v|
        name = k[/^service (.+)$/, 1]
        if name.nil?
          @params[k] = v
        else
          @params['services'][name] = v
        end
      end
      @params
    end

    def filter(conditions = {})
      res = params.dup
      filters = ''
      conditions.each do |k, v|
        v = v.to_s if v.is_a? Integer
        filters += " #{k} = #{v.inspect}"
        res['services'] = filter_by(res['services'], k.to_s, v)
      end
      XinetdConf.new(@conf_path, params: res, filters: filters)
    end

    private

    # Retrieve the provided field from all configured services.
    #
    # @param [String] field name, e.g. `socket_type`
    # @return [Array[String]] all values of this field across services
    def services_field(field)
      params['services'].values.compact.flatten
                        .map { |x| x.params[field] }.flatten.compact
    end

    def match_condition(sth, condition)
      case sth
      # this does Regex-matching as well as string comparison
      when condition
        true
      else
        false
      end
    end

    # Filter services by a criteria. This allows for search queries for
    # certain values.
    #
    # @param [Hash] service collection
    # @param [String] search key you want to query
    # @param [Any] search value that the key should match
    # @return [Hash] filtered service collection
    def filter_by(services, k, v)
      if k == 'service'
        return Hash[services.find_all { |name, _| match_condition(v, name) }]
      end
      Hash[services.map { |name, service_arr|
        found = service_arr.find_all { |service|
          match_condition(service.params[k], v)
        }
        found.empty? ? nil : [name, found]
      }.compact]
    end

    def read_content(path = @conf_path)
      return @contents[path] if @contents.key?(path)
      file = inspec.file(path)
      if !file.file?
        return skip_resource "Can't find file \"#{path}\""
      end

      @contents[path] = file.content
      if @contents[path].empty? && file.size > 0
        return skip_resource "Can't read file \"#{path}\""
      end

      @contents[path]
    end
  end
end
