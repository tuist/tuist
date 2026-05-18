FROM typesense/typesense:27.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl jq ca-certificates cron \
  && rm -rf /var/lib/apt/lists/*

COPY bin/index-docc /opt/docsearch/index-docc
COPY bin/index-github /opt/docsearch/index-github
COPY bin/run-indexers.sh /opt/docsearch/run-indexers.sh
COPY bin/entrypoint.sh /opt/docsearch/entrypoint.sh
COPY config/docsearch.json /opt/docsearch/docsearch.json
COPY config/docsearch-forum.json /opt/docsearch/docsearch-forum.json

RUN chmod +x /opt/docsearch/index-docc /opt/docsearch/index-github \
    /opt/docsearch/run-indexers.sh /opt/docsearch/entrypoint.sh

ENTRYPOINT ["/opt/docsearch/entrypoint.sh"]
