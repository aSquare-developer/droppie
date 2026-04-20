# droppie

`droppie` is a Vapor-based backend for user authentication, route tracking, profile management, and route PDF export.

## What It Does

The API currently supports:

- email-based registration and login
- email verification flow
- password reset flow
- JWT access + refresh tokens
- current user and profile endpoints
- paginated route management
- health and readiness endpoints
- optional route distance enrichment through Redis + Google Routes API
- optional PDF generation for route reports through `wkhtmltopdf`

## Tech Stack

- Swift 6
- Vapor 4
- Fluent + PostgreSQL
- JWT
- Redis / Queues Redis Driver
- Leaf

## Main Endpoints

### Health

- `GET /health/live`
- `GET /health/ready`

### Auth

- `POST /api/register`
- `POST /api/login`
- `POST /api/refresh`
- `POST /api/verify-email`
- `POST /api/verify-email/request`
- `POST /api/forgot-password`
- `POST /api/reset-password`
- `GET /api/me`

### Profile

- `GET /api/users/profile`
- `PUT /api/users/profile`

### Routes

- `GET /api/users/routes?page=1&per=20`
- `POST /api/users/route`
- `DELETE /api/users/route/:id`
- `GET /api/users/routes/generate?month=4&year=2026&currentOdometer=276743.0`

## Local Development

### Requirements

- Xcode / Swift toolchain with Swift 6 support
- PostgreSQL
- optional: Redis
- optional: Docker Desktop if you want to use `docker compose`

### Environment

Start from [.env.example](/Users/arturanissimov/Desktop/vapor/droppie/.env.example).

Important variables:

- `JWT_SECRET`
- `DB_HOST_NAME`
- `DB_USER_NAME`
- `DB_PASSWORD`
- `DB_NAME`
- `AUTO_MIGRATE`
- `JWT_ACCESS_TOKEN_LIFETIME_SECONDS`
- `JWT_REFRESH_TOKEN_LIFETIME_SECONDS`

Optional variables:

- `REDIS_URL`
- `GOOGLE_ROUTES_API_KEY`
- `WKHTMLTOPDF_PATH`
- `CORS_ALLOWED_ORIGINS`

### Run With Swift

1. Create a PostgreSQL database.
2. Configure your environment variables.
3. Start the app:

```bash
swift build
JWT_SECRET=change-me \
AUTO_MIGRATE=true \
DB_HOST_NAME=127.0.0.1 \
DB_USER_NAME=droppie \
DB_PASSWORD=change-me \
DB_NAME=droppie \
.build/debug/droppie serve --env production --hostname 127.0.0.1 --port 8080
```

### Run With Docker Compose

The repository includes [docker-compose.yml](/Users/arturanissimov/Desktop/vapor/droppie/docker-compose.yml) for a simple local stack.

Useful commands:

```bash
docker compose build
docker compose up app
docker compose up db
docker compose run migrate
docker compose down -v
```

## Email Verification And Password Reset

The project supports two email delivery modes:

- `logger` mode for local development
- `resend` mode for real email delivery

### Local Development

By default, the app uses logger mode.

In that mode:

- verification tokens are written to the application logs
- password reset tokens are written to the application logs

That means you can fully test the flow locally without integrating an email provider first.

### Production Email Delivery

To send real emails through Resend, configure:

- `EMAIL_PROVIDER=resend`
- `EMAIL_API_KEY`
- `EMAIL_FROM_ADDRESS`

Optional email variables:

- `EMAIL_FROM_NAME`
- `EMAIL_REPLY_TO_ADDRESS`
- `APP_BASE_URL`
- `EMAIL_API_BASE_URL`

If `APP_BASE_URL` is configured, verification and reset emails also include clickable links with the token in the query string.

## Route Distance And PDF Notes

- If `REDIS_URL` or `GOOGLE_ROUTES_API_KEY` is missing, routes are still saved, but distance calculation is skipped.
- If `wkhtmltopdf` is not installed or not configured, PDF generation will not be available.
- `GET /api/users/routes/generate` requires route distances to already exist.

## Security Notes

The project already includes:

- auth rate limiting
- security headers middleware
- configurable CORS
- HSTS toggle
- access and refresh token flow
- email verification before full login

## Postman

Ready-to-import collection:

- [docs/postman/droppie-api.postman_collection.json](/Users/arturanissimov/Desktop/vapor/droppie/docs/postman/droppie-api.postman_collection.json)

Usage guide:

- [docs/postman/README.md](/Users/arturanissimov/Desktop/vapor/droppie/docs/postman/README.md)

## Current Limitations

- refresh tokens are stateless JWTs and are not yet stored/revoked server-side
- there is still very little automated test coverage
- PDF generation depends on a local/system binary

## CI

GitHub Actions CI is configured in [.github/workflows/ci.yml](/Users/arturanissimov/Desktop/vapor/droppie/.github/workflows/ci.yml).

It runs on every `push` and `pull_request` and currently does:

- `swift package resolve`
- `swift build`
- `swift test`
