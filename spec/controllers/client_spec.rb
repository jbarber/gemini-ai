# frozen_string_literal: true

require_relative '../../ports/dsl/gemini-ai'
require_relative '../../components/errors'

RSpec.describe Gemini do
  it 'avoids unsupported services' do
    expect do
      described_class.new(
        credentials: {
          service: 'unknown-service'
        }
      )
    end.to raise_error(
      Gemini::Errors::UnsupportedServiceError,
      "Unsupported service: 'unknown-service'."
    )
  end

  it 'avoids conflicts with credential keys' do
    expect do
      described_class.new(
        credentials: {
          service: 'vertex-ai-api',
          api_key: 'key',
          file_path: 'path',
          file_contents: 'contents'
        }
      )
    end.to raise_error(
      Gemini::Errors::ConflictingCredentialsError,
      "You must choose either 'api_key', 'file_contents', or 'file_path'."
    )

    expect do
      described_class.new(
        credentials: {
          service: 'vertex-ai-api',
          file_path: 'path',
          file_contents: 'contents'
        }
      )
    end.to raise_error(
      Gemini::Errors::ConflictingCredentialsError,
      "You must choose either 'file_contents', or 'file_path'."
    )
  end

  context 'when a Faraday configuration block is provided' do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:model) { 'this-is-for-testing' }

    it 'calls the Faraday configuration block' do
      stubs.post("https://generativelanguage.googleapis.com/v1/models/#{model}:generateContent") do |env|
        expect(env.request_headers['X-Custom-Header']).to eq('TestValue')
        [
          200,
          { 'Content-Type': 'application/json' },
          '{}'
        ]
      end

      client = described_class.new(
        credentials: {
          service: 'generative-language-api',
          api_key: 'key'
        },
        options: {
          model: model
        }
      ) do |faraday|
        faraday.adapter :test, stubs
        faraday.headers['X-Custom-Header'] = 'TestValue'
      end

      client.generate_content({ contents: { role: 'user', parts: { text: 'hi!' } } })

      stubs.verify_stubbed_calls
    end
  end
end
