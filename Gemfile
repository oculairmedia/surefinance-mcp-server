# frozen_string_literal: true

source "https://rubygems.org"

ruby "3.4.4"

# MCP SDK - fast-mcp for HTTP transport
gem "fast-mcp", git: "https://github.com/yjacquin/fast-mcp.git"

# Web server
gem "rack", "~> 3.1"
gem "rackup", "~> 2.2"
gem "puma", "~> 6.5"
gem "rack-attack", "~> 6.7"

# Database (for connecting to SureFinance DB)
gem "pg", "~> 1.5"
gem "activerecord", "~> 8.0"

# JSON handling
gem "oj", "~> 3.16"

# Authentication
gem "jwt", "~> 2.10"

# Environment variables
gem "dotenv", "~> 3.1"

group :development, :test do
  gem "debug", "~> 1.9"
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.69", require: false
  gem "rubocop-rspec", "~> 3.3", require: false
end
