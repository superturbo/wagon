require 'json'
require 'base64'

module Locomotive::Wagon

  # Rewrites stale MongoDB ObjectIDs (from a previous Locomotive instance) with their
  # new counterparts, inside any nested Hash/Array/String structure. Handles both raw
  # 24-hex ids and ids embedded in Base64 encoded /_locomotive-link/ payloads (RTE links).
  class ReferenceRemapper

    # a single pass: an encoded link token OR a raw hex id, so the raw id substitution
    # can never touch the characters of a base64 payload
    TOKEN_REGEXP = %r{(?:(/_locomotive-link/)([A-Za-z0-9+/=]+))|(\b[0-9a-f]{24}\b)}i

    # @param mapping [Hash] old id (lowercase) => new id
    def initialize(mapping)
      @mapping = mapping
    end

    def remap(value)
      case value
      when Hash   then value.each_with_object({}) { |(key, _value), hash| hash[key] = remap(_value) }
      when Array  then value.map { |_value| remap(_value) }
      when String then remap_string(value)
      else value
      end
    end

    private

    def remap_string(string)
      string.gsub(TOKEN_REGEXP) do
        if (id = Regexp.last_match(3))
          @mapping[id.downcase] || id
        else
          prefix, encoded = Regexp.last_match(1), Regexp.last_match(2)
          prefix + (remap_encoded_link(encoded) || encoded)
        end
      end
    end

    # nil keeps the original token byte-for-byte: idempotency for already remapped
    # links and safety for payloads we cannot decode
    def remap_encoded_link(encoded)
      payload  = JSON.parse(Base64.decode64(encoded))
      remapped = remap(payload)
      remapped == payload ? nil : Base64.strict_encode64(remapped.to_json)
    rescue JSON::ParserError, ArgumentError, EncodingError
      nil
    end

  end

end
