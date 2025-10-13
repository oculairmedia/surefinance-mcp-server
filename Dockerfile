# syntax=docker/dockerfile:1.6

FROM ruby:3.4.4-alpine

WORKDIR /app

RUN apk add --no-cache build-base libpq-dev

COPY Gemfile Gemfile.lock .
RUN bundle install

COPY . .

CMD ["bundle", "exec", "ruby", "lib/surefinance_mcp.rb"]
