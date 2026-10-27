FROM typesense/typesense:27.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl jq ca-certificates cron \
  && sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf \
  && update-ca-certificates \
  && rm -rf /var/lib/apt/lists/*
RUN --mount=type=bind,from=certificate-trust,target=/certificate-trust bash /certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt

COPY bin/index-docc /opt/docsearch/index-docc
COPY bin/index-github /opt/docsearch/index-github
COPY bin/index-github-releases /opt/docsearch/index-github-releases
COPY bin/run-indexers.sh /opt/docsearch/run-indexers.sh
COPY bin/entrypoint.sh /opt/docsearch/entrypoint.sh
COPY config/docsearch.json /opt/docsearch/docsearch.json
COPY config/docsearch-forum.json /opt/docsearch/docsearch-forum.json

RUN chmod +x /opt/docsearch/index-docc /opt/docsearch/index-github /opt/docsearch/index-github-releases \
    /opt/docsearch/run-indexers.sh /opt/docsearch/entrypoint.sh

ENTRYPOINT ["/opt/docsearch/entrypoint.sh"]
