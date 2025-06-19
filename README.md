# Rails Live Reload

[![RailsJazz](https://github.com/igorkasyanchuk/rails_time_travel/blob/main/docs/my_other.svg?raw=true)](https://www.railsjazz.com)

[!["Buy Me A Coffee"](https://github.com/igorkasyanchuk/get-smart/blob/main/docs/snapshot-bmc-button-small.png?raw=true)](https://buymeacoffee.com/igorkasyanchuk)

![RailsLiveReload](docs/rails_live_reload.gif)

This is the simplest and probably the most robust way to add live reloading to your Rails app.

Just add the gem and thats it, now you have a live reloading. **You don't need anything other than this gem for live reloading to work**.

Works with:

- views (EBR/HAML/SLIM) (the page is reloaded only when changed views which were rendered on the page)
- partials
- CSS/JS
- helpers (if configured)
- YAML locales (if configured)
- on the "crash" page, so it will be reloaded as soon as you make a fix

The page is reloaded fully with `window.location.reload()` to make sure that every chage will be displayed.

## Usage

### Basic Usage

Just add this gem to the Gemfile (in development environment) and start the `rails s`.

The gem works automatically with zero configuration for most Rails applications.

> **Note**: If you're using a custom JavaScript build process (esbuild, Webpack, Vite, etc.), see [Custom JavaScript Build Integration](#7-custom-javascript-build-integration-esbuild-webpack-etc) for instructions on integrating the JavaScript manually.

### Usage Scenarios

#### 1. Standard Rails Application
```ruby
# Gemfile
group :development do
  gem "rails_live_reload"
end
```

No additional configuration needed. The gem will automatically:
- Reload pages when views change (only if the view was rendered)
- Hot-reload CSS files without full page refresh
- Trigger full page reload for JS, image, and other asset changes

#### 2. Custom Asset Pipeline Setup
If your assets take longer than 200ms to compile, you may want to watch the compiled output instead:

```ruby
# config/initializers/rails_live_reload.rb
RailsLiveReload.configure do |config|
  # Watch compiled assets instead of source files
  config.watch %r{public/assets/.+\.(css|js)$}, reload: :always

  # Ignore source files to avoid double reloading
  config.ignore %r{app/assets/}
  config.ignore %r{app/javascript/}
end
```

#### 3. Watching Additional Files
```ruby
# config/initializers/rails_live_reload.rb
RailsLiveReload.configure do |config|
  # Reload when helpers change
  config.watch %r{app/helpers/.+\.rb}, reload: :always

  # Reload when locale files change
  config.watch %r{config/locales/.+\.yml}, reload: :always

  # Reload when decorators change (if using Draper)
  config.watch %r{app/decorators/.+\.rb}, reload: :always

  # Watch specific controller changes
  config.watch %r{app/controllers/admin/.+\.rb}, reload: :always
end
```

#### 4. Monorepo or Custom Structure
```ruby
# config/initializers/rails_live_reload.rb
RailsLiveReload.configure do |config|
  # Watch files in custom directories
  config.watch %r{engines/admin/app/views/.+\.(erb|haml|slim)$}
  config.watch %r{shared/components/.+\.(erb|haml|slim)$}

  # Ignore large directories that shouldn't trigger reloads
  config.ignore %r{node_modules/}
  config.ignore %r{vendor/bundle/}
  config.ignore %r{coverage/}
end
```

#### 5. Development with Docker
The gem works seamlessly with Docker. Make sure your Rails server is accessible and the WebSocket connection can be established.

#### 6. Using with Turbo/Turbolinks
The gem automatically integrates with Turbo and Turbolinks, re-establishing WebSocket connections after navigation.

#### 7. Custom JavaScript Build Integration (esbuild, Webpack, etc.)

By default, the gem automatically injects its JavaScript into your HTML pages. However, if you prefer to manage the JavaScript through your own build process (esbuild, Webpack, Vite, etc.), you can do so by:

1. **Disabling automatic injection** and **copying the source JavaScript**:

```ruby
# config/initializers/rails_live_reload.rb
RailsLiveReload.configure do |config|
  # Disable automatic script injection
  config.enabled = false # This disables the middleware injection
end
```

2. **Copy the JavaScript source** from the gem to your project:

```bash
# Copy the source JavaScript to your project
cp $(bundle show rails_live_reload)/javascript/index.js app/javascript/rails_live_reload.js
```

3. **Configure your build tool** to include the JavaScript:

**For esbuild:**
```javascript
// esbuild.config.js
const esbuild = require('esbuild')

esbuild.build({
  entryPoints: ['app/javascript/application.js'],
  bundle: true,
  outdir: 'app/assets/builds',
  // ... other options
}).catch(() => process.exit(1))
```

```javascript
// app/javascript/application.js
import RailsLiveReload from './rails_live_reload.js'

// Start Rails Live Reload
if (process.env.NODE_ENV === 'development') {
  document.addEventListener('DOMContentLoaded', () => {
    RailsLiveReload.start()
  })
}
```

**For Webpack:**
```javascript
// webpack.config.js
module.exports = {
  entry: './app/javascript/application.js',
  // ... other configuration
}
```

```javascript
// app/javascript/application.js
import RailsLiveReload from './rails_live_reload.js'

if (process.env.NODE_ENV === 'development') {
  document.addEventListener('DOMContentLoaded', () => {
    RailsLiveReload.start()
  })
}
```

4. **Add the configuration script** to your layout manually:

```erb
<!-- app/views/layouts/application.html.erb -->
<% if Rails.env.development? %>
  <script id="rails-live-reload-options" type="application/json">
    <%= {
      files: [], # You can leave this empty for manual integration
      time: Time.now.to_i,
      url: "/rails/live/reload"
    }.to_json.html_safe %>
  </script>
<% end %>
```

5. **Enable the WebSocket server** without middleware:

```ruby
# config/initializers/rails_live_reload.rb
if Rails.env.development?
  # Enable just the WebSocket server, not the middleware
  RailsLiveReload.configure do |config|
    config.enabled = true
    # The server will still run, but won't inject scripts
  end

  # Start the file watcher
  RailsLiveReload::Watcher.init
end
```

**Alternative: Keep gem enabled but prevent script injection**

If you want to keep the gem's automatic file watching but prevent script injection, you can override the middleware:

```ruby
# config/initializers/rails_live_reload.rb
if Rails.env.development?
  RailsLiveReload.configure do |config|
    # Keep the gem enabled for file watching
    config.enabled = true
  end

  # Override the middleware to not inject scripts
  module RailsLiveReload
    module Middleware
      class Base
        private

        def make_new_response(body, nonce)
          # Return body unchanged - no script injection
          body
        end
      end
    end
  end
end
```

**Benefits of custom integration:**
- Full control over when and how the JavaScript loads
- Integration with your existing build pipeline
- Ability to customize the JavaScript behavior
- Better performance through bundling with your other assets
- Source maps and debugging support from your build tools

## Requirements

- **Rails**: 5.0+ (tested with Rails 6.x and 7.x)
- **Ruby**: 2.6+ 
- **Browser**: Any modern browser with WebSocket support
- **Development Environment**: Works in development mode by default

### Dependencies

The gem automatically includes these dependencies:
- `listen` - File system monitoring
- `websocket-driver` - WebSocket communication
- `nio4r` - Non-blocking I/O operations

## Installation

Add this line to your application's Gemfile:

```ruby
group :development do
  gem "rails_live_reload"
end
```

And then execute:
```bash
$ bundle
```

## Configuration

### Basic Setup

For most applications, no configuration is needed. The gem works out of the box with sensible defaults.

### Advanced Configuration

To customize the behavior, run the generator to create an initializer:

```bash
rails generate rails_live_reload:install
```

This creates `config/initializers/rails_live_reload.rb` with the following options:

```ruby
RailsLiveReload.configure do |config|
  # WebSocket endpoint (default: "/rails/live/reload")
  # config.url = "/rails/live/reload"

  # Enable/disable the gem (default: Rails.env.development?)
  # config.enabled = Rails.env.development?

  # Default watched patterns (automatically included)
  # Views: app/views/.+\.(erb|haml|slim)$
  # Assets: (app|vendor)/(assets|javascript)/\w+/(.+\.(css|js|html|png|jpg|ts|jsx)).*

  # Add custom file patterns to watch
  # config.watch %r{app/helpers/.+\.rb}, reload: :always
  # config.watch %r{config/locales/.+\.yml}, reload: :always

  # Ignore specific patterns
  # config.ignore %r{node_modules/}
  # config.ignore %r{\.git/}
end if defined?(RailsLiveReload)
```

### Configuration Options

#### `config.url`
- **Default**: `"/rails/live/reload"`
- **Purpose**: WebSocket endpoint URL
- **Example**: `config.url = "/my-custom/reload-path"`

#### `config.enabled`
- **Default**: `Rails.env.development?`
- **Purpose**: Enable/disable live reloading
- **Example**: `config.enabled = Rails.env.development? || Rails.env.staging?`

#### `config.watch(pattern, reload: strategy)`
- **Purpose**: Add file patterns to watch
- **Parameters**:
  - `pattern`: Regular expression matching file paths
  - `reload`: Strategy (`:on_change` or `:always`)
- **Reload Strategies**:
  - `:on_change`: Only reload if the file was actually rendered on the current page
  - `:always`: Always reload when this file changes
- **Examples**:
  ```ruby
  # Watch helper files (always reload)
  config.watch %r{app/helpers/.+\.rb}, reload: :always

  # Watch locale files (always reload)
  config.watch %r{config/locales/.+\.yml}, reload: :always

  # Watch specific view directories
  config.watch %r{app/views/admin/.+\.(erb|haml|slim)$}
  ```

#### `config.ignore(pattern)`
- **Purpose**: Ignore specific file patterns
- **Examples**:
  ```ruby
  config.ignore %r{node_modules/}
  config.ignore %r{\.git/}
  config.ignore %r{tmp/}
  ```

### Default File Patterns

The gem automatically watches these patterns:

1. **Views** (`reload: :on_change`):
   - `app/views/.+\.(erb|haml|slim)$`
   - Only reloads if the view was rendered on the current page

2. **Assets** (`reload: :always`):
   - `(app|vendor)/(assets|javascript)/\w+/(.+\.(css|js|html|png|jpg|ts|jsx)).*`
   - Always triggers reload when these files change
   - CSS files trigger hot-reload (no full page refresh)
   - Other asset files trigger full page reload


## How it works

There are 3 main parts:

1) listener of file changes (using `listen` gem)
2) collector of rendered views (see rails instrumentation)
3) JavaScript client that communicates with server and triggers reloading when needed

## Notes

The default configuration assumes that you either use asset pipeline, or that your assets compile quickly (on most applications asset compilation takes around 50-200ms), so it watches for changes in `app/assets` and `app/javascript` folders, this will not be a problem for 99% of users, but in case your asset compilation takes couple of seconds, this might not work propperly, in that case we would recommend you to add configuration to watch output folder.

## Contributing

You are welcome to contribute. See list of `TODO's` below.

## TODO

- reload CSS without reloading the whole page?
- smarter reload if there is a change in helper (check methods from rendered views?)
- more complex rules? e.g. if "user.rb" file is changed - reload all pages with rendered "users" views
- check with older Rails versions
- CI (github actions)
- auto reload when rendered controller was changed
- support for watching files outside Rails root
- integration with popular CSS frameworks (Tailwind, Bootstrap)
- configuration UI/dashboard for easier setup

## Troubleshooting

### Common Issues

#### `Too many open files - pipe`
**Solution**: Increase file descriptor limits
```bash
ulimit -n 10000
```

#### Live reload not working
**Possible causes and solutions**:

1. **WebSocket connection failed**
   - Check browser developer console for WebSocket errors
   - Ensure Rails server is running and accessible
   - Verify no firewall blocking WebSocket connections

2. **Files not being watched**
   - Check if your files match the default patterns
   - Add custom patterns in initializer if needed
   - Verify file paths are relative to Rails root

3. **Asset compilation too slow**
   - If assets take >200ms to compile, watch compiled output instead:
   ```ruby
   config.watch %r{public/assets/.+\.(css|js)$}, reload: :always
   config.ignore %r{app/assets/}
   ```

4. **Docker/Container issues**
   - Ensure Rails server binds to `0.0.0.0` not just `localhost`
   - Check port forwarding configuration
   - Verify WebSocket connections can reach the container

#### Socket path too long
**Error**: Socket path exceeds 104 characters
**Solution**: The gem automatically falls back to `/tmp/` directory. No action needed.

#### CSS hot-reload not working
**Possible causes**:
- CSS files not matching the default asset pattern
- Custom asset compilation setup
- Missing `<link>` tags with `rel="stylesheet"`

**Solution**: Add specific CSS patterns:
```ruby
config.watch %r{app/assets/stylesheets/.+\.css$}, reload: :always
```

#### Page reloads too frequently
**Cause**: Files matching patterns with `reload: :always`
**Solution**: Use `reload: :on_change` for view files:
```ruby
config.watch %r{app/views/.+\.erb$}, reload: :on_change
```

### Debug Mode

To see what files are being watched, check the Rails server output when starting:
```
Watching: /path/to/your/app
  app/views/.+\.(erb|haml|slim)$ => on_change
  (app|vendor)/(assets|javascript)/\w+/(.+\.(css|js|html|png|jpg|ts|jsx)).* => always
```

### Browser Compatibility

The gem works with all modern browsers that support WebSockets:
- Chrome/Chromium
- Firefox
- Safari
- Edge

### Performance Considerations

- The gem uses minimal resources in development
- File watching is handled by the efficient `listen` gem
- WebSocket connections are lightweight
- CSS hot-reloading avoids full page refreshes, improving development speed

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

[<img src="https://github.com/igorkasyanchuk/rails_time_travel/blob/main/docs/more_gems.png?raw=true"
/>](https://www.railsjazz.com/?utm_source=github&utm_medium=bottom&utm_campaign=rails_live_reload)


[!["Buy Me A Coffee"](https://github.com/igorkasyanchuk/get-smart/blob/main/docs/snapshot-bmc-button-small.png?raw=true)](https://buymeacoffee.com/igorkasyanchuk)
