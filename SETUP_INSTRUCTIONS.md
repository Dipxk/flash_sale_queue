# Setup Instructions — Flash Sale Queue System

## 1. Install Ruby (use a version manager, not your system Ruby)

**macOS (Homebrew):**
```bash
brew install rbenv ruby-build
rbenv install 3.2.3
rbenv global 3.2.3
echo 'eval "$(rbenv init - zsh)"' >> ~/.zshrc   # or ~/.bashrc if using bash
source ~/.zshrc
ruby -v   # should print 3.2.3
```

**Windows:** install via [RubyInstaller](https://rubyinstaller.org/) (pick the version with "WITH DEVKIT").

**Linux:** use `rbenv` the same way as macOS, or your distro's version manager of choice.

## 2. Install Rails

```bash
gem install rails
rails -v   # confirm it works
```

## 3. Install PostgreSQL and Redis

**macOS:**
```bash
brew install postgresql@16 redis
brew services start postgresql@16
brew services start redis
```

**Windows/Linux:** install Postgres via your OS installer, and Redis via WSL/Docker if on Windows (`docker run -p 6379:6379 redis`).

## 4. Generate the Rails app

```bash
rails new flash_sale_queue --database=postgresql
cd flash_sale_queue
```

## 5. Add gems

Open `Gemfile` and add these lines (see `Gemfile_additions.txt` in this folder for the exact lines):
```ruby
gem "sidekiq"
gem "redis"
```

Then run:
```bash
bundle install
```

## 6. Copy in the provided files

Copy each file from this starter kit into the matching path in your generated Rails app:
- `db/migrate/*.rb` → your app's `db/migrate/`
- `app/models/*.rb` → your app's `app/models/`
- `app/controllers/*.rb` → your app's `app/controllers/`
- `app/jobs/*.rb` → your app's `app/jobs/`
- Contents of `routes_snippet.rb` → paste into your app's `config/routes.rb`

## 7. Set up the database

```bash
rails db:create
rails db:migrate
```

## 8. Run Sidekiq (in a separate terminal, Redis must be running)

```bash
bundle exec sidekiq
```

## 9. Run the Rails server

```bash
rails server
```

Visit `http://localhost:3000` — you'll need to add views or test via `rails console` / API requests (curl/Postman) since this starter is API-focused, not UI-focused. See README.md for how to test the flow end-to-end.
