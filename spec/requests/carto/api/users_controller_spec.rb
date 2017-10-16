# encoding: utf-8

require_relative '../../../spec_helper_min'
require 'support/helpers'
require_relative '../../../../app/controllers/carto/api/users_controller'

describe Carto::Api::UsersController do
  include_context 'organization with users helper'
  include Warden::Test::Helpers
  include HelperMethods

  before(:all) do
    @headers = { 'CONTENT_TYPE' => 'application/json' }
  end

  describe 'me' do
    it 'returns a hash with current user info' do
      user = @organization.owner
      carto_user = Carto::User.where(id: user.id).first

      get_json api_v3_users_me_url(user_domain: user.username, api_key: user.api_key), @headers do |response|
        expect(response.status).to eq(200)

        expect(response.body[:default_fallback_basemap].with_indifferent_access).to eq(user.default_basemap)

        dashboard_notifications = carto_user.notifications_for_category(:dashboard)
        expect(response.body[:dashboard_notifications]).to eq(dashboard_notifications)
        expect(response.body[:can_change_email]).to eq(user.can_change_email?)
        expect(response.body[:auth_username_password_enabled]).to eq(true)
        expect(response.body[:should_display_old_password]).to eq(user.should_display_old_password?)
        expect(response.body[:can_change_password]).to eq(true)
        expect(response.body[:plan_name]).to eq('Free')
        expect(response.body[:services]).to eq(user.get_oauth_services)
      end
    end

    it 'returns a hash with only config if there is no authenticated user' do
      get_json api_v3_users_me_url, @headers do |response|
        expect(response.status).to eq(200)
        expect(response.body).to have_key(:config)
        expect(response.body[:user_frontend_version]).to eq(CartoDB::Application.frontend_version)
      end
    end
  end

  describe 'update_me' do
    context 'account updates' do
      before(:each) do
        @user = FactoryGirl.create(:user, password: 'foobarbaz', password_confirmation: 'foobarbaz')
      end

      after(:each) do
        @user.destroy
      end

      let(:url_options) do
        {
          user_domain: @user.username,
          user_id: @user.id,
          api_key: @user.api_key
        }
      end

      it 'updates account data for the given user' do
        payload = {
          user: {
            email: 'foo@bar.baz',
            old_password: 'foobarbaz',
            new_password: 'bazbarfoo',
            confirm_password: 'bazbarfoo'
          }
        }

        put_json api_v3_users_update_me_url(url_options), payload, @headers do |response|
          expect(response.status).to eq(200)

          @user.refresh
          expect(@user.email).to eq('foo@bar.baz')
        end
      end

      it 'gives a status code 200 if payload is empty' do
        put_json api_v3_users_update_me_url(url_options), {}, @headers do |response|
          expect(response.status).to eq(200)
        end
      end

      it 'gives an error if email is invalid' do
        payload = { user: { email: 'foo@' } }

        put_json api_v3_users_update_me_url(url_options), payload, @headers do |response|
          expect(response.status).to eq(400)
          expect(response.body[:message]).to eq("Error updating your account details")
          expect(response.body[:errors]).to have_key(:email)
        end
      end

      it 'gives an error if old password is invalid' do
        payload = { user: { old_password: 'idontknow', new_password: 'barbaz', confirm_password: 'barbaz' } }

        put_json api_v3_users_update_me_url(url_options), payload, @headers do |response|
          expect(response.status).to eq(400)
          expect(response.body[:message]).to eq("Error updating your account details")
          expect(response.body[:errors]).to have_key(:old_password)
        end
      end

      it 'gives an error if new password and confirmation are not the same' do
        payload = { user: { old_password: 'foobarbaz', new_password: 'foofoo', confirm_password: 'barbar' } }

        put_json api_v3_users_update_me_url(url_options), payload, @headers do |response|
          expect(response.status).to eq(400)
          expect(response.body[:message]).to eq("Error updating your account details")
          expect(response.body[:errors]).to have_key(:new_password)
        end
      end

      it 'returns 401 if user is not logged in' do
        put_json api_v3_users_update_me_url(url_options.except(:api_key)), @headers do |response|
          expect(response.status).to eq(401)
        end
      end
    end

    context 'profile updates' do
      before(:each) do
        @user = FactoryGirl.create(:user)
      end

      after(:each) do
        @user.destroy
      end

      let(:url_options) do
        {
          user_domain: @user.username,
          user_id: @user.id,
          api_key: @user.api_key
        }
      end

      it 'updates profile data for the given user' do
        payload = {
          user: {
            name: 'Foo',
            last_name: 'Bar',
            website: 'https://carto.rocks',
            description: 'Foo Bar Baz',
            location: 'Anywhere',
            twitter_username: 'carto',
            disqus_shortname: 'carto',
            avatar_url: 'http://carto.rocks/avatar.jpg'
          }
        }

        put_json api_v3_users_update_me_url(url_options), payload, @headers do |response|
          expect(response.status).to eq(200)

          expect(response.body[:name]).to eq('Foo')
          expect(response.body[:last_name]).to eq('Bar')
          expect(response.body[:website]).to eq('https://carto.rocks')
          expect(response.body[:description]).to eq('Foo Bar Baz')
          expect(response.body[:location]).to eq('Anywhere')
          expect(response.body[:twitter_username]).to eq('carto')
          expect(response.body[:disqus_shortname]).to eq('carto')
          expect(response.body[:avatar_url]).to eq('http://carto.rocks/avatar.jpg')
        end
      end

      it 'does not update fields not present in the user hash' do
        payload = {
          user: {
            name: 'Foo',
            last_name: 'Bar',
            website: 'https://carto.rocks'
          }
        }
        old_description = @user.description
        old_location = @user.location
        old_twitter_username = @user.twitter_username

        put_json api_v3_users_update_me_url(url_options), payload, @headers do |response|
          expect(response.status).to eq(200)

          expect(response.body[:name]).to eq('Foo')
          expect(response.body[:last_name]).to eq('Bar')
          expect(response.body[:website]).to eq('https://carto.rocks')
          expect(response.body[:description]).to eq(old_description)
          expect(response.body[:location]).to eq(old_location)
          expect(response.body[:twitter_username]).to eq(old_twitter_username)
        end
      end

      it 'sets field to nil if key is present in the hash with a nil value' do
        fields_to_check = [
          :name, :last_name, :website, :description, :location, :twitter_username,
          :disqus_shortname, :available_for_hire
        ]

        fields_to_check.each do |field|
          payload = { user: { field => nil } }
          put_json api_v3_users_update_me_url(url_options), payload, @headers do |response|
            expect(response.status).to eq(200)
            @user.refresh
            expect(@user.values[field]).to be_nil
          end
        end
      end

      it 'returns 401 if user is not logged in' do
        payload = { user: { name: 'Foo' } }

        put_json api_v3_users_update_me_url(url_options.except(:api_key)), payload, @headers do |response|
          expect(response.status).to eq(401)
        end
      end
    end
  end

  describe 'delete_me' do
    before(:each) do
      @user = FactoryGirl.create(:user, password: 'foobarbaz', password_confirmation: 'foobarbaz')
    end

    let(:url_options) do
      {
        user_domain: @user.username,
        user_id: @user.id,
        api_key: @user.api_key
      }
    end

    it 'deletes the authenticated user' do
      payload = { deletion_password_confirmation: 'foobarbaz' }

      delete_json api_v3_users_delete_me_url(url_options), payload, @headers do |response|
        expect(response.status).to eq(200)
        expect(Carto::User.exists?(@user.id)).to be_false
      end
    end

    context 'failures in deletion' do
      after(:each) do
        @user.destroy
      end

      it 'gives an error if deletion password confirmation is invalid' do
        payload = { deletion_password_confirmation: 'idontknow' }

        delete_json api_v3_users_delete_me_url(url_options), payload, @headers do |response|
          expect(response.status).to eq(400)
          expect(response.body[:message]).to eq("Error deleting user: Password does not match")
        end
      end

      it 'returns 401 if user is not logged in' do
        delete_json api_v3_users_delete_me_url(url_options.except(:api_key)), @headers do |response|
          expect(response.status).to eq(401)
        end
      end
    end
  end
end
