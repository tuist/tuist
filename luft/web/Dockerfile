# Image for the Luft web edge served at luft.work (infra/helm/luft-web).
# Build context: luft/web. The site comes from Once (`once build LuftWeb`) as
# the `site` build context: --build-context site=luft/.once/out/LuftWeb/dist.
# Vite keeps content-hashed files under /assets/, which nginx.conf caches as
# immutable.
FROM nginxinc/nginx-unprivileged:1.29-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=site . /usr/share/nginx/html/

EXPOSE 8080
