require 'json'

module Parsers
  class BaseParser
    attr_reader :ruler, :raw_data

    # @param ruler [String] the ruler definition from the bank record
    def initialize(ruler)
      @ruler = parse_ruler(ruler)
    end

    # Parse raw statement content and return structured JSON
    # @param raw_data [String] raw file content from the bank
    # @return [Hash] { balances: [...], transactions: [...] }
    def parse(raw_data)
      @raw_data = raw_data
      lines = raw_data.to_s.lines.map(&:chomp)

      {
        balances:     extract_balances(lines),
        transactions: extract_transactions(lines)
      }
    end

    # Convenience: parse and return JSON string
    def parse_to_json(raw_data)
      JSON.pretty_generate(parse(raw_data))
    end

    # Return the parser name (class name without module)
    def self.parser_name
      name.split('::').last
    end

    # Registry: look up a parser class by name string
    def self.for(name)
      klass = Parsers.const_get(name)
      raise ArgumentError, "#{name} is not a valid parser" unless klass < BaseParser
      klass
    rescue NameError
      raise ArgumentError, "Unknown parser: #{name}"
    end

    protected

    # Parse the ruler string into a structured definition.
    # Default format: one field per line, "field_name:start:length" (fixed-width)
    # or "field_name:index" (delimited).
    # Subclasses may override for custom ruler formats.
    def parse_ruler(ruler_str)
      return {} if ruler_str.nil? || ruler_str.strip.empty?

      fields = {}
      ruler_str.strip.lines.each do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')

        parts = line.split(':')
        field_name = parts[0].strip

        if parts.length == 3
          # Fixed-width: field_name:start:length
          fields[field_name] = { start: parts[1].to_i, length: parts[2].to_i }
        elsif parts.length == 2
          # Delimited: field_name:column_index
          fields[field_name] = { index: parts[1].to_i }
        end
      end
      fields
    end

    # Extract a field value from a line using ruler definition
    def extract_field(line, field_name)
      defn = @ruler[field_name]
      return nil unless defn

      if defn.key?(:start)
        # Fixed-width extraction
        line[defn[:start], defn[:length]].to_s.strip
      elsif defn.key?(:index)
        # Delimited extraction (comma by default)
        parts = line.split(delimiter)
        idx = defn[:index]
        idx < parts.length ? parts[idx].strip : nil
      end
    end

    # Override in subclasses to set the delimiter for delimited files
    def delimiter
      ','
    end

    # Override in subclasses
    def extract_balances(_lines)
      []
    end

    # Override in subclasses
    def extract_transactions(_lines)
      []
    end
  end
end
