#!/bin/sh

# Generate config.js from environment variables
cat <<EOF > /usr/share/nginx/html/config.js
window.env = {
  GRAPHQL_HTTP: "${GRAPHQL_HTTP:-http://localhost:5000/graphql}",
  GRAPHQL_WS: "${GRAPHQL_WS:-ws://localhost:5000/graphql}"
};
EOF

# Start Nginx
nginx -g "daemon off;"
