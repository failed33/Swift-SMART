# How to run standalone_launch (work in progress)

As the OAuth2 library client(?) only accepts HTTPS, but our SMART laucher uses HTTP, we need to remap and handle this. We installed Caddy to provide a reverse proxy map from HTTP to HTTPS. To do so, start the caddy server with the following command, where the Caddyfile is the actual path to the Caddyfile.

## SMART_REDIRECT environment variable

Set `SMART_REDIRECT` in `standalone_launch.env` to the exact redirect URI that is registered with your authorization server (for example `http://127.0.0.1:8765/callback`). The standalone launch tests use this value for both the OAuth authorize request and for the local loopback listener, so the harness will attempt to bind to the host, port, and path you provide. If you leave `SMART_REDIRECT` unset, the listener defaults to `http://127.0.0.1:<random-port>/callback`.

```bash
brew install mkcert
mkcert -install
```

```bash
caddy start --config Caddyfile
```

To stop the caddy server call:

```bash
caddy stop
```
