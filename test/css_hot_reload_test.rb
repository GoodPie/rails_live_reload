require "test_helper"

class CssHotReloadTest < ActiveSupport::TestCase
  def setup
    RailsLiveReload.instance_variable_set(:@_config, nil)
  end

  test "Command detects CSS-only changes correctly" do
    # Mock changes with only CSS files
    css_changes = ["app/assets/stylesheets/application.css", "vendor/assets/stylesheets/theme.css"]
    command = RailsLiveReload::Command.new("dt" => "0", "files" => "[]")

    # Override the changes method to return our CSS files
    command.define_singleton_method(:changes) { css_changes }

    assert command.css_only_changes?, "Should detect CSS-only changes"
    assert_equal "CSS_RELOAD", command.payload[:command], "Should return CSS_RELOAD command"
  end

  test "Command detects mixed changes correctly" do
    # Mock changes with CSS and other files
    mixed_changes = ["app/assets/stylesheets/application.css", "app/views/users/index.html.erb"]
    command = RailsLiveReload::Command.new("dt" => "0", "files" => "[]")

    # Override the changes method to return mixed files
    command.define_singleton_method(:changes) { mixed_changes }

    assert_not command.css_only_changes?, "Should not detect as CSS-only changes"
    assert_equal "RELOAD", command.payload[:command], "Should return RELOAD command for mixed changes"
  end

  test "Command detects non-CSS changes correctly" do
    # Mock changes with only non-CSS files
    non_css_changes = ["app/views/users/index.html.erb", "app/controllers/users_controller.rb"]
    command = RailsLiveReload::Command.new("dt" => "0", "files" => "[]")

    # Override the changes method to return non-CSS files
    command.define_singleton_method(:changes) { non_css_changes }

    assert_not command.css_only_changes?, "Should not detect as CSS-only changes"
    assert_equal "RELOAD", command.payload[:command], "Should return RELOAD command for non-CSS changes"
  end

  test "css_file? method detects CSS files correctly" do
    command = RailsLiveReload::Command.new("dt" => "0", "files" => "[]")

    assert command.css_file?("app/assets/stylesheets/application.css"), "Should detect .css files"
    assert command.css_file?("vendor/assets/stylesheets/theme.css.scss"), "Should detect .css.scss files"
    assert_not command.css_file?("app/views/users/index.html.erb"), "Should not detect .erb files"
    assert_not command.css_file?("app/assets/javascripts/application.js"), "Should not detect .js files"
  end

  test "Watcher css_file? method works correctly" do
    config = RailsLiveReload::Config.new
    watcher = RailsLiveReload::Watcher.new(config: config)

    assert watcher.send(:css_file?, "app/assets/stylesheets/application.css"), "Should detect .css files"
    assert watcher.send(:css_file?, "vendor/assets/stylesheets/theme.css.scss"), "Should detect .css.scss files"
    assert_not watcher.send(:css_file?, "app/views/users/index.html.erb"), "Should not detect .erb files"
    assert_not watcher.send(:css_file?, "app/assets/javascripts/application.js"), "Should not detect .js files"
  end
end
