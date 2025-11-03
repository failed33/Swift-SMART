# How to run standalone_launch (work in progress)

As the OAuth2 library client(?) only accepts HTTPS, but our SMART laucher uses HTTP, we need to remap and handle this. We installed Caddy to provide a reverse proxy map from HTTP to HTTPS. To do so, start the caddy server with the following command, where the Caddyfile is the actual path to the Caddyfile.

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
