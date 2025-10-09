#!/bin/bash
echo "insert the URL with this format 'https://urlofyoursite.com'"
URL=""
read URL
curl -Iv $URL 2>&1 | grep -E "subject:|issuer:|expire date|SSL certificate verify|^< HTTP/"

