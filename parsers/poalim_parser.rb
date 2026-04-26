require_relative 'base_parser'

module Parsers
  # Parser for בנק הפועלים (Bank Hapoalim) statements.
  # Expects fixed-width files.
  # Ruler format: one field per line as "field_name:start_position:length"
  #
  # Example ruler:
  #   date:0:10
  #   value_date:10:10
  #   reference:20:12
  #   description:32:30
  #   debit:62:15
  #   credit:77:15
  #   balance:92:15
  #   currency:107:3
  class PoalimParser < BaseParser
    protected

    def extract_balances(lines)
      balances = []
      lines.each do |line|
        next if line.strip.empty? || line.length < 10

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
        next if line.strip.empty? || line.length < 10

        date = extract_field(line, 'date')
        next unless date && !date.empty?

        debit  = extract_field(line, 'debit')
        credit = extract_field(line, 'credit')

        amount = if credit && !credit.strip.empty? && parse_amount(credit) != 0
                   parse_amount(credit)
                 elsif debit && !debit.strip.empty?
                   -parse_amount(debit)
                 else
                   0
                 end

        {
          date:        date.strip,
          value_date:  (extract_field(line, 'value_date') || date).strip,
          description: (extract_field(line, 'description') || '').strip,
          reference:   (extract_field(line, 'reference') || '').strip,
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
