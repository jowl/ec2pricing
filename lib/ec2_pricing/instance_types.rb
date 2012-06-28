# encoding: utf-8

require 'nokogiri'


module Ec2Pricing
  class InstanceTypes
    include Caching

    INSTANCE_TYPES_DATA_URL = 'http://aws.amazon.com/ec2/instance-types/'

    def types
      load!
      @instance_types
    end

    def load!
      return if defined? @instance_type

      data = cached('instance_types') do
        open(INSTANCE_TYPES_DATA_URL).read
      end

      document = Nokogiri::HTML(data)
      instance_properties = []
      paragraphs = document.xpath('//div[@class = "yui-b"]/p')
      until paragraphs.empty?
        paragraph = paragraphs.shift
        text = paragraph.text
        if text.include?('Instance') && (text.end_with?('Instance') || text.end_with?('default*'))
          text.sub!(/(?<=Instance).+$/, '')
          instance_properties << {:name => text}.merge(parse_description(paragraphs.shift.text.split("\n")))
        end
      end
      @instance_types = instance_properties.each_with_object({}) do |instance, acc|
        acc[instance[:type]] = instance
      end
    end

    INSTANCE_TYPES_CACHE_PATH = File.join(CACHE_DIR, 'instance-types.html')

    def parse_description(description_lines)
      properties = {:notes => []}
      description_lines.each do |line|
        case line
        when /([\d.]+ [MG]B) (?:of )?memory/
          properties[:ram] = $1
        when /([\d.]+) EC2 Compute Units? \((\d) virtual core/
          properties[:ecus] = $1.to_f
          properties[:cores] = $2.to_i
        when /([\d.]+) EC2 Compute Units? \((\d)([^\)]+)\)/
          properties[:ecus] = $1.to_f
          properties[:cores] = $2.to_i
          properties[:notes] << "#{$2}#{$3}"
        when /Up to \d+ EC2 Compute Units/
          properties[:ecus] = 0
          properties[:cores] = 1
          properties[:notes] << line
        when /([\d.]+ GB) (?:of )?instance storage/
          properties[:disk] = $1
        when /32-bit or 64-bit platform/
          properties[:architectures] = [32, 64]
        when /64-bit platform/
          properties[:architectures] = [64]
        when /I\/O Performance: ([\w\s]+)/
          properties[:io] = $1.downcase.strip
        when /API name: (\S+)/
          properties[:type] = $1
        when /EBS storage only/
          properties[:notes] << $&
        when /2 x NVIDIA Tesla/
          properties[:notes] << $&
        else
          $stderr.puts("Unmatched description line: #{line}")
        end
      end
      properties.delete(:notes) if properties[:notes].empty?
      properties
    end
  end
end