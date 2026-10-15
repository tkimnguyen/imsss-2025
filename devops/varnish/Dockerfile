# syntax=docker/dockerfile:1
FROM varnish:7.6

LABEL maintainer="T Kim Nguyen <tkn@alumni.uwaterloo.ca>" \
      org.label-schema.name="imsss-2025-varnish" \
      org.label-schema.description="IMSSS 2025 Varnish image." \
      org.label-schema.vendor="T Kim Nguyen"

COPY etc/varnish.vcl /etc/varnish/default.vcl
