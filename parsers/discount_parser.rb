require_relative 'base_parser'

module Parsers
  # Parser for בנק דיסקונט (Discount Bank) statements.
  # Expects tab-delimited files.
  # Ruler format: one field per line as "field_name:column_index"
  #
  # Example ruler:
  #   date:0
  #   value_date:1
  #   reference:2
  #   description:3
  #   amount:4
  #   balance:5
  #   currency:6
  class DiscountParser < BaseParser
    def delimiter
      "\t"
    end

    protected

    def extract_balances(lines)
      balances = []
      lines.each do |line|
        next if line.strip.empty?

        balance_val = extract_field(line, 'balance')
        next unless balance_val && !balance_val.empty?

        currency = extract_field(line, 'currency') || 'ILS'
        date     = extract_field(line, 'date')

        balances << {
          date:     date,
          currency: currency.strip,
          amount:   parse_amount(balance_val)
        }
      end

      balances.group_by { |b| b[:currency] }.map do |curr, entries|
        entries.last.merge(currency: curr)
      end
    end

    def extract_transactions(lines)
      lines.filter_map do |line|
        next if line.strip.empty?

        date = extract_field(line, 'date')
        next unless date && !date.empty?

        amount_str = extract_field(line, 'amount')
        amount = parse_amount(amount_str || '0')

        {
          date:        date,
          value_date:  extract_field(line, 'value_date') || date,
          description: extract_field(line, 'description'),
          reference:   extract_field(line, 'reference'),
          amount:      amount,
          balance:     parse_amount(extract_field(line, 'balance') || '0')
        }
      end
    end

    private

    def parse_amount(str)
      str.to_s.gsub(/[^\d.\-]/, '').to_f
    end
  end
end
