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
        stubs.post("https://generativelanguage.googleapis.com/v1/models/#{model}:generateContent?key=test-key") do |env|
          body = JSON.parse(env.body)
          # Labels should NOT appear in the request body for generative-language-api
          expect(body).not_to have_key('labels')
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
      let(:expected_url) { "https://#{region}-aiplatform.googleapis.com/v1/projects/#{project_id}/locations/#{region}/publishers/google/models/#{model}:generateContent" }

      before do
        # Mock the token fetch
        allow_any_instance_of(Google::Auth::ServiceAccountCredentials)
          .to receive(:fetch_access_token!)
          .and_return({ 'access_token' => 'mock-token' })
      end

      it 'adds labels to request body' do
        stubs.post(expected_url) do |env|
          body = JSON.parse(env.body)
          expect(body['labels']).to eq({
            'prompt_class' => 'identify_competitors',
            'feature' => 'competitor_analysis',
            'environment' => 'test'
          })
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

      it 'converts symbol keys to strings' do
        labels_with_symbols = { prompt_class: 'test', feature: 'embedding' }

        stubs.post(expected_url) do |env|
          body = JSON.parse(env.body)
          expect(body['labels']).to eq({
            'prompt_class' => 'test',
            'feature' => 'embedding'
          })
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

        client.generate_content({ contents: { role: 'user', parts: { text: 'hi!' } } }, labels: labels_with_symbols)

        stubs.verify_stubbed_calls
      end

      it 'preserves original payload when adding labels' do
        stubs.post(expected_url) do |env|
          body = JSON.parse(env.body)
          expect(body['contents']).to eq({ 'role' => 'user', 'parts' => { 'text' => 'hi!' } })
          expect(body['labels']).to eq(labels)
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
    end
  end
end
