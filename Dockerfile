FROM elixir:1.19-otp-28-alpine AS build

WORKDIR /app

RUN apk add --no-cache build-base git

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get --only prod

ENV MIX_ENV=prod
COPY config/ config/
COPY lib/ lib/
RUN mix compile

RUN mix release

# ── Runtime image ──────────────────────────────────────────────────────────────
FROM alpine:3.19 AS runtime

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app
COPY --from=build /app/_build/prod/rel/miak_tech ./

ENV HOME=/app
EXPOSE 4000

CMD ["./bin/miak_tech", "start"]
