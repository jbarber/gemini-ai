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

  context 'labels parameter' do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:model) { 'gemini-2.0-flash' }
    let(:labels) do
      {
        'prompt_class' => 'identify_competitors',
        'feature' => 'competitor_analysis',
        'environment' => 'test'
      }
    end

    context 'with generative-language-api' do
      it 'ignores labels (not supported by this API)' do
        # Labels should NOT appear in the URL for generative-language-api
        stubs.post("https://generativelanguage.googleapis.com/v1/models/#{model}:generateContent?key=test-key") do |_env|
          [200, { 'Content-Type': 'application/json' }, '{}']
        end

        client = described_class.new(
          credentials: {
            service: 'generative-language-api',
            api_key: 'test-key'
          },
          options: { model: }
        ) do |faraday|
          faraday.adapter :test, stubs
        end

        client.generate_content({ contents: { role: 'user', parts: { text: 'hi!' } } }, labels:)

        stubs.verify_stubbed_calls
      end
    end

    context 'with vertex-ai-api' do
      let(:project_id) { 'test-project' }
      let(:region) { 'us-central1' }
      let(:service_account_json) do
        {
          type: 'service_account',
          project_id:,
          private_key_id: 'key-id',
          private_key: OpenSSL::PKey::RSA.new(2048).to_pem,
          client_email: 'test@test-project.iam.gserviceaccount.com',
          client_id: '123',
          auth_uri: 'https://accounts.google.com/o/oauth2/auth',
          token_uri: 'https://oauth2.googleapis.com/token'
        }.to_json
      end

      before do
        # Mock the token fetch
        allow_any_instance_of(Google::Auth::ServiceAccountCredentials)
          .to receive(:fetch_access_token!)
          .and_return({ 'access_token' => 'mock-token' })
      end

      it 'adds labels as query parameters' do
        expected_url = "https://#{region}-aiplatform.googleapis.com/v1/projects/#{project_id}/locations/#{region}/publishers/google/models/#{model}:generateContent?labels.prompt_class=identify_competitors&labels.feature=competitor_analysis&labels.environment=test"

        stubs.post(expected_url) do |_env|
          [200, { 'Content-Type': 'application/json' }, '{}']
        end

        client = described_class.new(
          credentials: {
            service: 'vertex-ai-api',
            file_contents: service_account_json,
            region:
          },
          options: { model: }
        ) do |faraday|
          faraday.adapter :test, stubs
        end

        client.generate_content({ contents: { role: 'user', parts: { text: 'hi!' } } }, labels:)

        stubs.verify_stubbed_calls
      end

      it 'escapes special characters in label values' do
        labels_with_special = { 'key' => 'value with spaces & symbols' }
        expected_url = "https://#{region}-aiplatform.googleapis.com/v1/projects/#{project_id}/locations/#{region}/publishers/google/models/#{model}:generateContent?labels.key=value+with+spaces+%26+symbols"

        stubs.post(expected_url) do |_env|
          [200, { 'Content-Type': 'application/json' }, '{}']
        end

        client = described_class.new(
          credentials: {
            service: 'vertex-ai-api',
            file_contents: service_account_json,
            region:
          },
          options: { model: }
        ) do |faraday|
          faraday.adapter :test, stubs
        end

        client.generate_content({ contents: { role: 'user', parts: { text: 'hi!' } } }, labels: labels_with_special)

        stubs.verify_stubbed_calls
      end

      it 'skips nil label values' do
        labels_with_nil = { 'present' => 'value', 'missing' => nil }
        expected_url = "https://#{region}-aiplatform.googleapis.com/v1/projects/#{project_id}/locations/#{region}/publishers/google/models/#{model}:generateContent?labels.present=value"

        stubs.post(expected_url) do |_env|
          [200, { 'Content-Type': 'application/json' }, '{}']
        end

        client = described_class.new(
          credentials: {
            service: 'vertex-ai-api',
            file_contents: service_account_json,
            region:
          },
          options: { model: }
        ) do |faraday|
          faraday.adapter :test, stubs
        end

        client.generate_content({ contents: { role: 'user', parts: { text: 'hi!' } } }, labels: labels_with_nil)

        stubs.verify_stubbed_calls
      end
    end
  end
end
