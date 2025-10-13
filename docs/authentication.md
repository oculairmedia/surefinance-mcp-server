# Authentication Guide

The SureFinance MCP server supports two authentication strategies:

## API Key Authentication

- Clients provide an API key in the `X-API-Key` header.
- Keys are configured via the `API_KEY` environment variable.

## JWT Authentication

- Clients provide a JWT token in the `Authorization` header using the `Bearer` scheme.
- Tokens are validated against the `JWT_SECRET` environment variable.
- The server uses the HS256 signing algorithm.
